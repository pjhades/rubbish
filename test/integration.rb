require 'minitest/autorun'

def pwd(pid)
    `lsof -p #{pid} -a -d cwd | tail -n1 | awk '{print $NF}'`.strip
end

def children(pid)
    # Gets [comm, pid] pairs for processes whose parent is pid.
    # ps on osx does not have --ppid option
    `ps -o comm,pid,ppid | awk '/#{pid}$/{print $1,$2}'`.strip
                                                        .split("\n")
                                                        .map { |t| t.split }
end

class Integration < MiniTest::Unit::TestCase
    def test_command_execution
        rd, wr = IO.pipe
        shell = Process.fork do
            $stdin.reopen(rd)
            wr.close
            Process.exec('ruby', File.join(Dir.pwd, 'rubbish.rb'))
        end
        rd.close
        # Wait for the shell to start and chdir to home
        sleep(0.5)

        assert_equal Dir.home, pwd(shell)

        wr.puts 'cat -n | cat -n | cat -n'
        pids = children(shell)

        assert pids.length == 3
        assert pids.all? { |t| t[0] =~ /cat/ }

        pids.each { |t| Process.kill('SIGTERM', t.last.to_i) }
        Process.kill('SIGTERM', shell)
        Process.waitall
    end
end
