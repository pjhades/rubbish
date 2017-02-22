require 'termios'

$jobs = {}

class Job
    def initialize(lst)
        @pgid = nil
        @procs = []
        @lst = lst
    end

    def to_foreground
        Termios.tcsetpgrp($stdin, @pgid)
    end

    def restore_shell
        Termios.tcsetpgrp($stdin, $$)
    end

    def wait
        return if !@pgid
        pid, status = @procs.map { |pid| Process.wait2(pid) }
                            .find { |pid, status| pid == @procs.last }
        $env[:STATUS] = status.exitstatus == 0 ? 0 : 1
        restore_shell
        $jobs.delete(@pgid)
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

            @procs.push(pid)

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
            exit self.send(builtin_name(cmd.prog), cmd.argv)
        else
            Process.exec(prog, *cmd.argv)
        end
    end
end

def job_init
    # Note that SIGTTOU should be ignored before
    # we create out own process group
    Signal.trap('SIGTTOU', 'SIG_IGN')
    Signal.trap('SIGINT', 'SIG_IGN')
    Process.setpgid(0, 0)
    Termios.tcsetpgrp($stdin, $$)
end

def restore_child_signal_handler
    Signal.trap('SIGTTOU', 'SIG_DFL')
    Signal.trap('SIGINT', 'SIG_DFL')
end
