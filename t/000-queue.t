#!/usr/bin/perl

use warnings;
use strict;
use utf8;
use open qw(:std :utf8);
use lib qw(lib ../lib);

use Test::More tests    => 13;
use Encode qw(decode encode);
use Cwd 'cwd';
use File::Spec::Functions 'catfile';
use feature 'state';

BEGIN {
    # Подготовка объекта тестирования для работы с utf8
    my $builder = Test::More->builder;
    binmode $builder->output,         ":utf8";
    binmode $builder->failure_output, ":utf8";
    binmode $builder->todo_output,    ":utf8";

    use_ok 'Coro';
    use_ok 'DR::Tarantool', ':all';
    use_ok 'DR::Tarantool::StartTest';
    use_ok 'Time::HiRes', 'time';
}
my $t = DR::Tarantool::StartTest->run(
    cfg         => catfile(cwd, 'config/db/tarantool.cfg'),
    script_dir  => catfile(cwd, 'config/db')
);

sub tnt {
    state $tnt;
    unless($tnt) {
        $tnt = coro_tarantool
            host => 'localhost',
            port => $t->primary_port,
            spaces => {
                0   => {
                    name            => 'queue',
                    default_type    => 'STR',
                    fields          => [
                        qw(uuid tube status),
                        {
                            type => 'NUM',
                            name => 'event'
                        },
                        {
                            type => 'NUM',
                            name => 'pri'
                        },
                        'cid',

                        {
                            type => 'NUM',
                            name => 'started'
                        },
                        {
                            type => 'NUM',
                            name => 'ttl',
                        },
                        {
                            type => 'NUM',
                            name => 'ttr',
                        },
                        'task',
                    ],
                    indexes => {
                        0 => 'uuid',
                        1 => {
                            name => 'event',
                            fields => [qw(tube status event pri)]
                        }
                    }
                }
            },
    }
    $tnt;
};

ok tnt->ping, 'ping tarantool';
diag $t->log unless
    ok $t->started, 'Tarantool was started';
diag $t->log unless
    ok eval { tnt }, 'Client connected to';

my $sno = tnt->space('queue')->number;

my $task1 = tnt->call_lua('queue.put',
    [
        $sno,
        'tube_name',
        0,
        10,
        20,
        30,
        'task', 1 .. 10
    ]
)->raw;

is_deeply $task1, [ $task1->[0], 'task', 1 .. 10 ], 'task 1';

my $started = time;
my $task2 = tnt->call_lua('queue.put',
    [
        $sno,
        'tube_name',
        1,
        10,
        20,
        30,
        'task', 10 .. 20
    ]
)->raw;

is_deeply $task2, [ $task2->[0], 'task', 10 .. 20 ], 'task 2';

my $task1_t = tnt->call_lua('queue.take', [ $sno, 'tube_name', 5 ])->raw;
is_deeply $task1_t, $task1, 'task1 taken';

my $task2_t = eval {tnt->call_lua('queue.take', [ $sno, 'tube_name', 5 ])->raw};
is_deeply $task2_t, $task2, 'task2 taken';
cmp_ok time - $started, '>=', 1, 'delay more than 1 second';
cmp_ok time - $started, '<=', 3, 'delay less than 3 second';



