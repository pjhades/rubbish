def signal_init
    Signal.trap('SIGTTOU', 'SIG_IGN')
    Signal.trap('SIGINT', 'SIG_IGN')
end

def restore_child_signal_handler
    Signal.trap('SIGTTOU', 'SIG_DFL')
    Signal.trap('SIGINT', 'SIG_DFL')
end

def read_line(prompt)
    print prompt
    s = $stdin.gets
    s.strip unless s == nil
end

def repl
    input_lines = ''
    slash = false

    prompt = lambda do
        slash ? green($env[:PS2]) :
                blue($env[:PWD]) + " " + green($env[:PS1])
    end

    while line = read_line(prompt.call)
        input_lines += line
        if input_lines[-1] != '\\'
            input_lines.strip!
            valid, result = parse(input_lines)
            if !valid
                error("#{$shell}: invalid syntax:\n" +
                      "#{input_lines}\n" +
                      ' ' * result + '^')
            else
                run_list(result)
            end
            input_lines = ''
            slash = false
        else
            input_lines.chop!
            slash = true
        end
    end
end

def search_path(prog)
    # ./path/to/program
    return prog if File.exist?(prog)

    # search PATH
    $env[:PATH].each do |path|
        full_path = File.join(path, prog)
        return full_path if File.exist?(full_path)
    end

    false
end

def spawn_child(cmd, stdin, stdout, group_leader_pid)
    if !$builtins.include?(cmd.prog.to_sym) && !(prog = search_path cmd.prog)
        error("#{$shell}: Unknown command '#{cmd.prog}'")
        return false
    end

    Process.fork do 
        Process.setpgid(0, group_leader_pid ? group_leader_pid : 0)
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

def run_list(lst)
    if lst.length == 0
        $env[:STATUS] = 0
        return
    end

    # Do not fork if only a builtin is provided
    if lst.length == 1 && $builtins.include?(lst[0].prog.to_sym)
       $env[:STATUS] = self.send(builtin_name(lst[0].prog), lst[0].argv) ? 0 : 1
       return
    end

    children = []
    pipe = []
    stdin = $stdin
    stdout = $stdout

    group_leader_pid = nil
    success = lst.each_with_index do |cmd, i|
        if i < lst.length - 1
            pipe = IO.pipe
            stdout = pipe[1]
        else
            stdout = $stdout
        end

        pid = spawn_child(cmd, stdin, stdout, group_leader_pid)
        break false unless pid

        group_leader_pid = pid if !group_leader_pid
        Process.setpgid(pid, group_leader_pid)

        stdin.close unless stdin.equal?($stdin)
        stdout.close unless stdout.equal?($stdout)
        stdin = pipe[0]

        children.push(pid)
    end

    if !success
        children.each { |pid| Process.kill('SIGTERM', pid) }
        $env[:STATUS] = 1
        return
    end

    Termios.tcsetpgrp($stdin, group_leader_pid)

    pid, status = Process.waitall.find { |pid, status| pid == children.last }
    $env[:STATUS] = status.exitstatus == 0 ? 0 : 1

    Termios.tcsetpgrp($stdin, $$)
end
