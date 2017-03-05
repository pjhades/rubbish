require 'termios'

# List of all jobs
$jobs = []
# Maps PID to a job
$pid_job = {}
# Shell terminal attributes
$shell_attr = nil
# For `fg` and `jobs`, to determine current and previous job
$curr_job = nil
$prev_job = nil
# Number of SIGCHLD signals we received
$n_sigchld = 0

class Job
    def initialize(lst, cmd)
        # Index in $jobs list
        @index = -1
        # Process group id
        @pgid = nil
        # PIDs in this job
        @pids = []
        # Parsed command list
        @lst = lst
        # Command line
        @cmd = cmd
        # Terminal settings
        @attr = nil
        # State
        @state = 'Running'
        # Exit status of the last process in the pipe
        @exitstatus = nil
        # Number of children reaped
        @n_reaped = 0
        # Run in background
        @background = lst.last.argv.last == '&'
        lst.last.argv.pop if @background
    end

    attr_reader :lst, :cmd, :background
    attr_accessor :pgid, :pids, :last, :state, :exitstatus, :n_reaped

    def restore_shell
        @attr = Termios.tcgetattr($stdin)
        Termios.tcsetattr($stdin, Termios::TCSANOW, $shell_attr)
        Termios.tcsetpgrp($stdin, $$)
    end

    def to_foreground
        $shell_attr = Termios.tcgetattr($stdin)
        Termios.tcsetattr($stdin, Termios::TCSANOW, @attr ? @attr : $shell_attr)
        Termios.tcsetpgrp($stdin, @pgid)
    end

    def mark_reaped_child(pid, status)
        @n_reaped += 1
        $n_sigchld -= 1
        @exitstatus = status if pid == @pids.last
    end

    def cleanup(report = false)
        if @exitstatus.exited?
            $env[:STATUS] = @exitstatus.exitstatus
            @state = 'Done'
        else
            $env[:STATUS] = @exitstatus.termsig + 128
            @state = 'Terminated'
        end

        report_state if report

        @pids.each { |pid| $pid_job.delete(pid) }

        # Pick the new previous/current job.
        # We should never choose this dead job.
        can = [$prev_job, $curr_job, $jobs.first]
        idx = can.find_index { |job| !self.equal?(job) }
        curr = idx ? can[idx] : nil

        # $jobs may not have that many elements, but accessing
        # such an index would give us nil
        can = [$jobs.first, $jobs[1], $jobs[2]]
        idx = can.find_index { |job| !self.equal?(job) && !curr.equal?(job) }
        prev = idx ? can[idx] : nil

        set_curr_and_prev_job(curr, prev)
    end

    def report_state
        mark = self.equal?($curr_job) ? '+' :
               self.equal?($prev_job) ? '-' : ' '
        puts JOB_REPORT_FORMAT % [@index, mark, @pgid, @state, @cmd]
    end

    def wait
        return if !@pgid

        n_stopped = 0
        while @n_reaped < @pids.length && n_stopped < @pids.length - @n_reaped
            # Only wait for children in the foreground group
            pid, status = Process.waitpid2(-@pgid, Process::WUNTRACED)
            # If the child is stopped ...
            n_stopped += 1 if status.stopped?
            # ... or terminated
            mark_reaped_child(pid, status) if status.exited? || status.signaled?
        end

        if n_stopped == @pids.length
            # Mark the job stopped if all foreground children are stopped
            @state = 'Stopped'
        elsif @n_reaped == @pids.length
            # Clean up the job if all children are reaped
            cleanup
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

            if !@pgid
                @pgid = pid
                $jobs.push(self)
                @index = $jobs.length - 1
                set_curr_and_prev_job(self, $curr_job)
            end
            @pids.push(pid)
            $pid_job[pid] = self
            Process.setpgid(pid, @pgid)

            stdin.close unless stdin.equal?($stdin)
            stdout.close unless stdout.equal?($stdout)
            stdin = pipe[0]
        end

        if !success
            # Run failed, kill them all
            @pids.each do |pid|
                Process.kill('SIGKILL', pid)
                Process.waitpid2(pid)
                pid_job.delete(pid)
            end
            $jobs.delete(self)
            $env[:STATUS] = 1
            return
        end

        if !@background
            to_foreground
            wait
        end

        reap_haunting_children(true)
    end

    def continue
        set_curr_and_prev_job(self, $curr_job)
        to_foreground
        Process.kill('SIGCONT', -@pgid)
        wait

        reap_haunting_children
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

def set_curr_and_prev_job(curr, prev)
    $curr_job, $prev_job = curr, prev if !curr.equal?(prev) || !curr && !prev
end

def job_init
    # Note that SIGTTOU should be ignored before
    # we create out own process group
    Signal.trap('SIGTTOU', 'SIG_IGN')
    Signal.trap('SIGTTIN', 'SIG_IGN')

    # Record the number of dead children
    Signal.trap('SIGCHLD') { |sig| $n_sigchld += 1 }

    Process.setpgid(0, 0)
    Termios.tcsetpgrp($stdin, $$)
end

def restore_child_signal_handler
    Signal.trap('SIGTTIN', 'SIG_DFL')
    Signal.trap('SIGTTOU', 'SIG_DFL')
    Signal.trap('SIGTSTP', 'SIG_DFL')
    Signal.trap('SIGINT',  'SIG_DFL')
end

def reap_haunting_children(report = false)
    while $n_sigchld > 0
        pid, status = Process.waitpid2(-1, Process::WNOHANG)
        job = $pid_job[pid]
        job.mark_reaped_child(pid, status)
        if job.n_reaped == job.pids.length
            job.cleanup(report)
            $jobs.delete(job) if report
        end
    end
end
