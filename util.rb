{
    :red   => "\e[38;5;198m",
    :green => "\e[38;5;82m",
    :blue  => "\e[38;5;21m",
}.each_pair do |color_name, color_code|
    define_method color_name do |s|
        color_code + s + "\e[0m"
    end
end

def error(msg)
    $stderr.puts red(msg)
    false
end
