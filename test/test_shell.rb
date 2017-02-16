require 'minitest/autorun'

require_relative '../script.rb'

class TestParsing < MiniTest::Unit::TestCase
    def test_pipe
        cases = [
            ['', []],
            ['foo -a -b -c -d', [['foo', '-a', '-b', '-c', '-d']]],
            ['foo | bar | baz', [['foo'], ['bar'], ['baz']]],
            ['foo|bar|baz', [['foo'], ['bar'], ['baz']]],
            ['foo -f1 -f2 | bar -b1', [['foo', '-f1', '-f2'],
                                       ['bar', '-b1']]],
            # unfinished pipe
            ['foo|',      [false, 4]],
            # no command between pipes
            ['foo||bar',  [false, 4]],
            ['foo| |bar', [false, 5]],
        ]

        cases.each do |arg, expected|
            assert_equal expected, parse_pipe_and_quote(arg)
        end
    end

    def test_escape_sequence
        cases = [
            # \n\r\t
            ['\n\r\t', [["\n\r\t"]]],
            # ' |\n\r\t'
            ['\' |\n\r\t\'', [[' |\n\r\t']]],
            # " |\n\r\t"
            ['" |\n\r\t"', [[" |\n\r\t"]]],
            # '"'
            ['\'"\'', [['"']]],
            # "'"
            ['"\'"', [['\'']]],
            # '\"'
            ['\'\\"\'', [['\\"']]],
            # '\\'
            ['\'\\\\\'', [['\\\\']]],
            # "\\"
            ['"\\\\"', [['\\']]],

            # unfinished quotes
            ['foo \'bar', [false, 8]],
            ['foo "bar', [false, 8]],
        ]

        cases.each do |arg, expected|
            assert_equal expected, parse_pipe_and_quote(arg)
        end
    end

    def test_redir
        cases = [
            [['foo', '>x', '-b', '<y', '-a'],
             [['foo', '-b', '-a'],
              {$stdin  => [['y', 'r']],
               $stdout => [['x', 'w']],
               $stderr => [],
              }]],

            [['foo', '<x1', '<x2', '>y1', '>y2'],
             [['foo'],
              {$stdin  => [['x1', 'r'], ['x2', 'r']],
               $stdout => [['y1', 'w'], ['y2', 'w']],
               $stderr => [],
              }]],

            [['foo', '<x', '>y1', '&>y2'],
             [['foo'],
              {$stdin  => [['x', 'r']],
               $stdout => [['y1', 'w'], ['y2', 'w']],
               $stderr => [['y2', 'w']],
              }]],

            [['foo', '<x', '&>y'],
             [['foo'],
              {$stdin  => [['x', 'r']],
               $stdout => [['y', 'w']],
               $stderr => [['y', 'w']],
              }]],
        ]

        cases.each do |arg, expected|
            assert_equal expected, parse_redir(arg)
        end
    end
end
