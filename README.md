# Rubbish

A ruby-ish rubbish shell.


# How to run

Gems needed:

* [ruby-termios](https://github.com/arika/ruby-termios)

After installing them,

```shell
$ ruby rubbish.rb
```


# What we have now

* shell builtins
    - `cd`, `type`, `set`, `exit`, `echo`
* execution of external commands
* pipes
    - a single builtin spawns no process
    - piped commands all run in a new process
* redirections
    - `<`, `>`, `>>`, `&>`, `&>>`
* quotes
* escape sequence
    - `\r`, `\n`, `\t`
* colorized shell prompt

# Todo
See the issues.
