$builtins = []

def builtin_name(prog)
    return ('builtin_' + prog).to_sym
end

def define_builtin(name, &block)
    define_method(builtin_name(name.to_s), block)
    $builtins.push(name)
end

def check_arity(argv, valid_arity_values, sym)
    return error("#{sym}: Invalid number of arguments.") if
        !valid_arity_values.include?(argv.length)

    return true
end

def call_builtin(name, argv)
    self.send(name, argv)
end

define_builtin :cd do |argv|
    return false if !check_arity(argv, [0, 1], :cd)

    dir = (argv.length == 0) ? Dir.home : File.expand_path(argv[0])
    dir = (dir == '//' || dir == '/') ? dir : dir.gsub(/(\/)\/*$/, '\\1')

    return error("cd: Directory '#{dir}' does not exist.") if !Dir.exist?(dir)

    $env[:PWD] = dir
    Dir.chdir(dir)

    return true
end

define_builtin :set do |argv|
    return false if !check_arity(argv, [0, 1, 2], :set)

    case argv.length
    when 0
        $env.each_pair { |k, v| puts "#{k} #{v.is_a?(Array) ? v.join(':') : v}" }
    when 1
        $env[argv[0].to_sym] = nil
    else
        $env[argv[0].to_sym] = argv[1]
    end

    return true
end

define_builtin :exit do |argv|
    return false if !check_arity(argv, [0], :exit)
    exit
end

define_builtin :echo do |argv|
    puts argv.join(' ')
    return true
end

define_builtin :type do |argv|
    return false if !check_arity(argv, [1], :type)

    if $builtins.include?(argv[0].to_sym)
        puts "#{argv[0]} is a shell builtin"
        return true
    elsif path = search_path(argv[0])
        puts path
        return true
    end

    error("type: #{argv[0]}: not found")
end

define_builtin :jobs do |argv|
    return false if !check_arity(argv, [0], :jobs)

    $jobs.each_with_index do |job, i|
        mark = job.equal?($curr_job) ? '+' :
               job.equal?($prev_job) ? '-' : ' '
        puts "[%d]%c %d %-10s %s" % [i+1, mark, job.pgid, job.state, job.cmd]
    end

    return true
end

define_builtin :fg do |argv|
    return false if !check_arity(argv, [0, 1], :fg)

    job = argv.length == 0 ? $curr_job : $jobs[argv[0].to_i - 1]

    return error('fg: no such job') if !job

    job.continue
    return true
end
