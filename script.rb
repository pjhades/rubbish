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

    matches = cmd_str.map {|piece| /^(<|>|>>|&>|&>>)([^<>&]+)$/.match piece}
                     .select {|m| m}
    matches.each do |m|
        type, file = m[1..-1]
        if type == '<'
            redirs[$stdin].push [file, 'r']
        elsif type == '>' || type == '&>'
            redirs[$stdout].push [file, 'w']
            redirs[$stderr].push [file, 'w'] if type == '&>'
        else
            redirs[$stdout].push [file, 'a']
            redirs[$stderr].push [file, 'a'] if type == '&>>'
        end
    end

    return cmd_str - matches.map{|m| m[0]}, redirs
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
    
    input.split('|').map do |piece|
        cmd_str = piece.split
        cmd_str, redirs = parse_redir cmd_str
        Struct::Command.new(cmd_str[0], cmd_str[1..-1], redirs)
    end
end
