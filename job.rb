require 'termios'

$jobs = {}

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
    end

    attr_accessor :pgid, :procs, :lst, :last, :cmd

    def to_foreground
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
            return false if status.stopped?
        end

        $env[:STATUS] = @procs[@last].exitstatus == 0 ? 0 : 1
        $jobs.delete(@pgid)

        return true
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
                $jobs[@pgid] = self
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
    end
end

def spawn_child(cmd, stdin, stdout, pgid)
    if !$builtins.include?(cmd.prog.to_sym) && !(prog = search_path cmd.prog)
        error("#{$shell}: Unknown command '#{cmd.prog}'")
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

def restore_shell
    Termios.tcsetpgrp($stdin, $$)
end
