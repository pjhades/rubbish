$builtins = []

JOB_REPORT_FORMAT = "[%d]%c %d %-10s %s"

def builtin_name(prog)
    return ('builtin_' + prog).to_sym
end

def define_builtin(name, &block)
    define_method(builtin_name(name.to_s), block)
    $builtins.push(name)
end

def check_arity(argv, valid_arity_values, sym)
    return error("%s: Invalid number of arguments." % [sym]) if
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

    return error("cd: Directory '%s' does not exist." % [dir]) if !Dir.exist?(dir)

    $env[:PWD] = dir
    Dir.chdir(dir)

    return true
end

define_builtin :set do |argv|
    return false if !check_arity(argv, [0, 1, 2], :set)

    case argv.length
    when 0
        $env.each_pair do |k, v|
            puts "%s %s" % [k, v.is_a?(Array) ? v.join(':') : v]
        end
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
        puts "%s is a shell builtin" % [argv[0]]
        return true
    elsif path = search_path(argv[0])
        puts path
        return true
    end

    error("type: %s: not found" % [argv[0]])
end

define_builtin :jobs do |argv|
    return false if !check_arity(argv, [0], :jobs)

    # Reap any dead children before reporting
    reap_haunting_children

    $jobs.each { |job| job.report_state }
    $jobs -= $jobs.select { |job| job.state == 'Done' ||
                                  job.state == 'Terminated' }

    return true
end

define_builtin :fg do |argv|
    return false if !check_arity(argv, [0, 1], :fg)

    job = argv.length == 0 ? $curr_job : $jobs[argv[0].to_i - 1]

    return error("fg: no such job") if !job

    job.continue
    return true
end

define_builtin :debug do |argv|
    $jobs.each do |job|
        puts "job #{job.pgid} #{job.state} #{job.cmd}"
    end
    puts "curr: #{$curr_job ? $curr_job.pgid : 'n/a'}"
    puts "prev: #{$prev_job ? $prev_job.pgid : 'n/a'}"
end
