require 'termios'

def job_init
    Process.setpgid(0, 0)
    Termios.tcsetpgrp($stdin, $$)
end
