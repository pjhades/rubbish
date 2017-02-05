# Rubbish

A ruby-ish rubbish shell.


# How to run

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
* colorized shell prompt

# Todo

* Add test
* Add more features
