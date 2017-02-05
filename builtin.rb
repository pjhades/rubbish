$builtins = []

def builtin_name(prog)
    return ('builtin_' + prog).to_sym
end

def define_builtin(name, &block)
    define_method builtin_name(name.to_s), block
    $builtins.push name
end

def check_arity(argv, valid_arity_values, sym)
    return error("#{sym}: Invalid number of arguments.") if
        !valid_arity_values.include? argv.length
    true
end

define_builtin :cd do |argv|
    return false if !check_arity(argv, [0, 1], :cd)

    dir = argv.length == 0 ? Dir.home : File.expand_path(argv[0])
    return error("cd: The directory '#{dir}' does not exist.") if
        !Dir.exist? dir

    dir.gsub! /\/+$/, ''
    $env[:PWD] = dir
    Dir.chdir dir

    true
end

define_builtin :set do |argv|
    return false if !check_arity(argv, [0, 1, 2], :set)

    case argv.length
    when 0
        $env.each_pair {|k, v| puts "#{k} #{v.is_a?(Array) ? v.join(':') : v}"}
    when 1
        $env[argv[0].to_sym] = nil
    else
        $env[argv[0].to_sym] = argv[1]
    end

    true
end

define_builtin :exit do |argv|
    return false if !check_arity(argv, [0], :exit)
    exit
end

define_builtin :echo do |argv|
    puts argv.join ' '
    true
end

define_builtin :type do |argv|
    return false if !check_arity(argv, [1], :type)

    if $builtins.include? argv[0].to_sym
        puts "#{argv[0]} is a shell builtin"
        return true
    elsif path = search_path(argv[0])
        puts path
        return true
    end

    error "type: #{argv[0]}: not found"
end
