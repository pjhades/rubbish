Struct.new('Command',
           :prog,   # program name string
           :argv,   # arguments
           :redirs, # redirections, format [[file, mode] ...]
          )

def parse_redir(cmd_str)
    redirs = {
        $stdin => [],
        $stdout => [],
        $stderr => []
    }

    matches = cmd_str.map { |piece| /^(<|>|>>|&>|&>>)([^<>&]+)$/.match(piece) }
                     .select { |m| m }
    matches.each do |m|
        type, file = m[1..-1]
        if type == '<'
            redirs[$stdin].push([file, 'r'])
        elsif type == '>' || type == '&>'
            redirs[$stdout].push([file, 'w'])
            redirs[$stderr].push([file, 'w']) if type == '&>'
        else
            redirs[$stdout].push([file, 'a'])
            redirs[$stderr].push([file, 'a']) if type == '&>>'
        end
    end

    return cmd_str - matches.map { |m| m[0] }, redirs
end

# Poorman's command line parsing
# Return [true, -1] if the parsing succeeds, or [false, pos] otherwise,
# where pos indicates the position in the command string that causes
# the failure
def parse_pipe_and_quote(cmd_str, &block)
    # Splitted command and a certain piece of it
    cmd, arg = [], ''
    # Whether we're inside quotes
    in_single_quote = false
    in_double_quote = false
    # Whether we're scanning escape sequence
    escaped = false
    # If the last non-space character is an active pipe
    active_pipe = false

    (0 ... cmd_str.length).each do |i|
        case cmd_str[i]
        when ' '
            # Preserve spaces inside quotes
            if in_single_quote || in_double_quote
                arg += ' '
                next
            end

            # Or we've splitted a new piece
            if arg.length > 0
                cmd.push(arg)
                arg = ''
            end
            active_pipe = false

        when '|'
            # Preserve pipes inside quotes
            if in_single_quote || in_double_quote
                arg += cmd_str[i]
                active_pipe = false
            else
                # Or we have a new piece before the pipe
                cmd.push(arg) if arg.length > 0

                # Yay!
                yield cmd
                cmd = []
                arg = ''

                active_pipe = true
            end


        when "'"
            # Treat the single quote as it is if it's escaped
            # or we're inside double quotes
            if escaped || in_double_quote
                arg += cmd_str[i]
                escaped = false if escaped
            else
                in_single_quote = !in_single_quote
            end
            active_pipe = false

        when '"'
            # Treat the double quote as it is if it's escaped
            # or we're inside single quotes
            if escaped || in_single_quote
                arg += cmd_str[i]
                escaped = false if escaped
            else
                in_double_quote = !in_double_quote
            end
            active_pipe = false

        when '\\'
            # Treat escape sequence as it is if we're inside single quotes
            if escaped || in_single_quote
                arg += '\\'
                escaped = false if escaped
            else
                # Complain if there's nothing afterwards
                return [false, i] if i + 1 >= cmd_str.length
                # We are now ready for the escape sequence
                escaped = true
            end
            active_pipe = false

        else
            # Turn \n, \t, \r to themselves
            if escaped
                arg += cmd_str[i] == 'n' ? "\n" :
                       cmd_str[i] == 't' ? "\t" :
                       cmd_str[i] == 'r' ? "\r" : cmd_str[i]
                escaped = false
            else
                arg += cmd_str[i]
            end
            active_pipe = false
        end
    end

    # Complain if we've exhausted the command string
    # but ended up inside quotes
    return [false, cmd_str.length] if in_single_quote ||
                                      in_double_quote ||
                                      active_pipe
    # Collect the last splitted command
    if arg.length > 0
        cmd.push(arg)
        yield cmd
    end

    return [true, -1]
end

def parse(input)
    # TODO Now we assume that
    # - input has no ||, &&, &, and ;
    # - input has only commands possibly connected by pipes
    # - each command has the syntax
    #
    #     prog a/r a/r ...
    #
    #   where 'prog' is the executable or path to the executable
    #         'a/r'  is either an argument or redirection
    #
    #   each 'a/r' has no whitespace characters inside

    cmds = []
    valid, pos = parse_pipe_and_quote(input) do |cmd|
        cmd, redir = parse_redir(cmd)
        cmds.push(Struct::Command.new(cmd[0], cmd[1..-1], redir))
    end

    return valid ? [valid, cmds] : [valid, pos]
end
