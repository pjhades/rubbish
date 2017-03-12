require 'minitest/autorun'

def pwd(pid)
    `lsof -p #{pid} -a -d cwd | tail -n1 | awk '{print $NF}'`.strip
end

def children(pid)
    # Gets [comm, pid] pairs for processes whose parent is `pid`.
    # ps on osx does not have --ppid option
    `ps -o comm,pid,ppid | awk '/#{pid}$/{print $1,$2}'`\
        .strip
        .split("\n")
        .map { |t| t.split }
end

def state(pid)
    # Get the state of process `pid`
    `ps -o pid,stat | awk '/#{pid}/{print $2}'`.strip
end

class Integration < MiniTest::Unit::TestCase
    def setup
        @rd, @wr = IO.pipe
        @shell_pid = Process.fork do
            $stdin.reopen(@rd)
            $stdout.reopen('/dev/null', 'w')
            @wr.close
            Process.exec('ruby', File.join(Dir.pwd, 'rubbish.rb'))
        end
        @rd.close
        # Wait for the shell to start and chdir to home
        sleep(0.5)
    end

    def teardown
        Process.kill('SIGTERM', @shell_pid)
        Process.waitall
        @wr.close
    end

    def input_to_shell(cmd)
        @wr.puts cmd
    end

    def test_execute_pipe
        input_to_shell 'cat -n | cat -n | cat -n'
        pids = children(@shell_pid)

        assert pids.length == 3
        assert pids.all? { |t| t[0] =~ /cat/ }

        pids.each { |t| Process.kill('SIGKILL', t.last.to_i) }
    end

    def test_stop_and_continue_job
        input_to_shell 'cat'
        pids = children(@shell_pid)
        assert pids.length == 1

        cat_pid = pids.first[1].to_i
        assert state(cat_pid) =~ /S\+/

        Process.kill('SIGTSTP', cat_pid)
        assert state(cat_pid) =~ /T/

        input_to_shell 'fg 0'
        assert state(cat_pid) =~ /S\+/

        Process.kill('SIGKILL', cat_pid)
    end

    def test_terminate_running_job
        # Start job in foreground
        input_to_shell 'sleep 100'
        pids = children(@shell_pid)
        assert pids.length == 1

        sleep_pid = pids.first[1].to_i
        assert state(sleep_pid) =~ /S\+/
        Process.kill('SIGINT', sleep_pid)

        assert children(@shell_pid).length == 0

        # Start job in background
        input_to_shell 'sleep 100 &'
        pids = children(@shell_pid)
        assert pids.length == 1

        sleep_pid = pids.first[1].to_i
        assert state(sleep_pid) =~ /S/
        Process.kill('SIGTERM', sleep_pid)
        # Give the shell a chance to reap the child
        input_to_shell "jobs"

        assert children(@shell_pid).length == 0
    end
end
