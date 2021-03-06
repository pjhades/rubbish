require 'readline'

def repl
    input_lines = ''
    slash = false

    prompt = lambda do
        slash ? green($env[:PS2]) :
                blue($env[:PWD]) + " " + green($env[:PS1])
    end

    Signal.trap('SIGINT') { print "\n#{prompt.call}" }
    Signal.trap('SIGTSTP', 'SIG_IGN')

    # I'm not sure if there's a clean way to handle
    # multi-line input rather than this...
    while line = Readline.readline(prompt.call, false)
        input_lines += line
        if input_lines[-1] != '\\'
            input_lines.strip!
            Readline::HISTORY.push(input_lines)
            valid, result = parse(input_lines)
            if !valid
                error("%s: invalid syntax:\n%s\n%s" %
                      [$shell, input_lines, ' ' * result + '^'])
            elsif result.length > 0
                job = Job.new(result, input_lines)
                job.run
            end
            input_lines = ''
            slash = false
        else
            input_lines.chop!
            slash = true
        end

        reap_haunting_children(true)
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
