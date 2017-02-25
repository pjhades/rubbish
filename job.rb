require 'termios'

$jobs = []
$shell_attr = nil
$curr_job = nil
$prev_job = nil

class Job
    def initialize(lst, cmd)
        # process group id
        @pgid = nil
        # map pid to status
        @procs = {}
        # parsed command list
        @lst = lst
        # pid of last process in pipe
        @last = nil
        # command line
        @cmd = cmd
        # terminal settings
        @attr = nil
    end

    attr_reader :lst, :state, :cmd
    attr_accessor :pgid, :procs, :last

    def state
        stopped? ? 'stopped' :
            completed? ? 'completed' : 'running'
    end

    def restore_shell
        @attr = Termios.tcgetpgrp($stdin)
        Termios.tcsetattr($stdin, Termios::TCSANOW, $shell_attr)
        Termios.tcsetpgrp($stdin, $$)
    end

    def to_foreground
        $shell_attr = Termios.tcgetattr($stdin)
        Termios.tcsetattr($stdin, Termios::TCSANOW, @attr ? @attr : $shell_attr)
        Termios.tcsetpgrp($stdin, @pgid)
    end

    def stopped?
        @procs.each_key.any? { |pid| @procs[pid] && @procs[pid].stopped? }
    end

    def completed?
        @procs.each_key.all? { |pid| @procs[pid] && @procs[pid].exited? }
    end

    def wait
        return if !@pgid

        @procs.each_key do |pid|
            next if @procs[pid] && @procs[pid].exited?
            pid, status = Process.waitpid2(pid, Process::WUNTRACED)
            @procs[pid] = status
            break if status.stopped?
        end

        if completed?
            $env[:STATUS] = @procs[@last].exitstatus == 0 ? 0 : 1
            $jobs.delete(self)
        end

        restore_shell
    end

    def run
        if @lst.length == 0
            $env[:STATUS] = 0
            return
        end

        # Do not fork if only a builtin is provided
        if @lst.length == 1 && $builtins.include?(@lst[0].prog.to_sym)
            $env[:STATUS] = call_builtin(builtin_name(@lst[0].prog),
                                         @lst[0].argv) ? 0 : 1
            return
        end

        pipe = []
        stdin = $stdin
        stdout = $stdout

        success = @lst.each_with_index do |cmd, i|
            if i < @lst.length - 1
                pipe = IO.pipe
                stdout = pipe[1]
            else
                stdout = $stdout
            end

            pid = spawn_child(cmd, stdin, stdout, @pgid)
            break false unless pid

            @procs[pid] = nil
            @last = pid if i == @lst.length - 1
            if !@pgid
                @pgid = pid
                $jobs.push(self)
                shift_job(self)
            end
            Process.setpgid(pid, @pgid)

            stdin.close unless stdin.equal?($stdin)
            stdout.close unless stdout.equal?($stdout)
            stdin = pipe[0]
        end

        if !success
            @procs.each { |pid| Process.kill('SIGTERM', pid) }
            $env[:STATUS] = 1
            return
        end

        to_foreground
        wait
    end

    def continue
        shift_job(self)
        to_foreground
        Process.kill('SIGCONT', -@pgid)
        wait
    end
end

def spawn_child(cmd, stdin, stdout, pgid)
    if !$builtins.include?(cmd.prog.to_sym) && !(prog = search_path cmd.prog)
        error("%s: Unknown command '%s'" % [$shell, cmd.prog])
        return false
    end

    Process.fork do
        Process.setpgid(0, pgid ? pgid : 0)
        restore_child_signal_handler

        if !stdin.equal?($stdin)
            $stdin.reopen(stdin)
            stdin.close
        end

        if !stdout.equal?($stdout)
            $stdout.reopen(stdout)
            stdout.close
        end

        cmd.redirs[$stdin].each do |file, mode|
            File.open(file, mode) { |f| $stdin.reopen(f) }
        end

        cmd.redirs[$stdout].each do |file, mode|
            File.open(file, mode) do |f|
                $stdout.reopen(f)
                $stderr.reopen(f) if cmd.redirs[$stderr].include?([file, mode])
            end
        end

        if $builtins.include?(cmd.prog.to_sym)
            exit call_builtin(builtin_name(cmd.prog), cmd.argv)
        else
            Process.exec(prog, *cmd.argv)
        end
    end
end

def shift_job(job)
    $prev_job = $curr_job
    $curr_job = job
end

def job_init
    # Note that SIGTTOU should be ignored before
    # we create out own process group
    Signal.trap('SIGTTOU', 'SIG_IGN')
    Process.setpgid(0, 0)
    Termios.tcsetpgrp($stdin, $$)
end

def restore_child_signal_handler
    Signal.trap('SIGTTOU', 'SIG_DFL')
    Signal.trap('SIGTSTP', 'SIG_DFL')
    Signal.trap('SIGINT', 'SIG_DFL')
end
