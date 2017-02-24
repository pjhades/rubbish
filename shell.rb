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

    Signal.trap('SIGINT') { print "\n#{prompt.call}" }
    Signal.trap('SIGTSTP', 'SIG_IGN')

    while line = read_line(prompt.call)
        input_lines += line
        if input_lines[-1] != '\\'
            input_lines.strip!
            valid, lst = parse(input_lines)
            if !valid
                error("#{$shell}: invalid syntax:\n" +
                      "#{input_lines}\n" + ' ' * result + '^')
            elsif lst.length > 0
                job = Job.new(lst, input_lines)
                job.run
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

    return false
end
