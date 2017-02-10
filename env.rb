$env = {
    :PATH   => ['/bin', '/usr/bin'],
    :PWD    => Dir.home,
    :PS1    =>  "$ ",
    :PS2    => '... ',
    :STATUS => 0,
}

Dir.chdir($env[:PWD])
