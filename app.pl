#!/usr/bin/env perl
use strict;
use warnings;
use lib 'lib';
use utf8;
use Encode;
use Log::Dispatch;
use Log::Dispatch::File;
use Log::Dispatch::Screen;
use AnyEvent;
use AnyEvent::Twitter;
use AnyEvent::Twitter::Stream;
use AnyEvent::Tabelog::Search;

require 'config.pl';


my $config = config();

my $log_dispatcher = log_dispatcher_new($config->{log});
my $tabelog_client = AnyEvent::Tabelog::Search->new($config->{tabelog}{api_key});
my $twitter_client = AnyEvent::Twitter->new(%{$config->{twitter_bot}{oauth}});


my $hash_tag             = ''; # 'tkdhoncho';
my $bot_name             = ''; # '@tkdhoncho_bot';
my $twitter_filter_track = join ',', $hash_tag, $bot_name;
my $twitter_lunch_regexp;

read_keyword('./keyword.pl');


my %tabelog_data = ();
my $before_tweet = '';

my($stop,
$tabelog_loop, $get_tabelog_data,
$twitter_loop, $twitter_listener);


$log_dispatcher->info(get_now(time) . qq( [info] start to logging --> "$config->{log}{dispatch_file}{filename}"));

my $cv = AE::cv;

$stop = AE::io \*STDIN, 0, sub {
    chomp (my $input = <STDIN>);
    if ($input eq 'exit') {
        undef $stop;
        undef $tabelog_loop;
        undef $twitter_loop;
        $log_dispatcher->info(get_now() . qq( [info] finish to logging --> "$config->{log}{dispatch_file}{filename}"));
        $cv->send;
    }
};

$get_tabelog_data = sub {
        for my $p (1..3) {
            my $sub_cv = AE::cv;
            my $get; $get = sub {
                my $page  = shift;

                $log_dispatcher->info(get_now() . ' [info] fetch "tabelog api" page ' . $page);

                $tabelog_client->get(%{$config->{tabelog}{request}}, 'PageNum' => $page,
                    on_error => sub {
                        my $headers = shift;
                        my $message = get_now() . qq( [error] !! $headers->{Status} $headers->{Reason} "tabelog" ${page});
                        $log_dispatcher->error($message);
                        $sub_cv->croak($page);
                        return;
                    },
                    sub {
                        my($data, undef) = @_;

                        unless (@{$data->{Item}}) {
                            $log_dispatcher->error(get_now() . qq( [error] !! data empty "tabelog" ${page}));
                            $sub_cv->croak($page);
                            return;
                        }

                        undef $get;

                        for my $shop (@{$data->{Item}}) {
                            $tabelog_data{$shop->{Rcd}} = $shop;
                        }

                        $log_dispatcher->info(get_now() . qq( [info] get "tabelog" page ${page}));

                        $sub_cv->send;
                    }
                );
            };

            $get->($p);

            $sub_cv->cb(sub {
                my $page = $sub_cv->recv;
                if ($page) {
                    my $retry; $retry = AE::timer 5, 0, sub {
                        undef $retry;
                        $log_dispatcher->info(get_now() . ' [info] retry fetch "tabelog" $page');
                        $get->($page);
                    };
                }
            });
        }
};
$tabelog_loop = AE::timer 0, (60 * 60 * 6), $get_tabelog_data;

$twitter_loop = sub {
    $log_dispatcher->info(get_now() . shift);

    my $retry_message = qq( [info] retry to listen "twitter_listener");
    $twitter_listener = AnyEvent::Twitter::Stream->new(%{$config->{twitter_bot}{oauth}},
        timeout  => 45,
        method   => "filter",
        track    => $twitter_filter_track,
        on_error => sub {
            my $fatal = shift;
            $log_dispatcher->error(get_now() . qq( [error] ${fatal} "twitter_listener on_error"));
            my $t; $t = AE::timer 5, 0, sub {
                undef $t;
                $twitter_loop->($retry_message);
            };
        },
        on_eof => sub {
            my $handle = shift;
            $log_dispatcher->error(get_now() . qq( [error] ${handle} "twitter_listener on_eof"));
            my $t; $t = AE::timer 5, 0, sub {
                undef $t;
                $twitter_loop->($retry_message);
            };
        },
        on_tweet => sub {
            my $tweet = shift;
            if ($tweet->{user}{id} ne $config->{twitter_bot}{id}) {
                $log_dispatcher->info(get_now() . encode_utf8 qq( [info] get "$tweet->{text}" "twitter_listener on_tweet"));

                if ($tweet->{text} =~ /$bot_name/ and $tweet->{text} =~ $twitter_lunch_regexp) {
                    reply($tweet);
                    return 1;
                }

                if ($tweet->{text} =~ /$hash_tag/) {
                    qt($tweet);
                    return 1;
                }

                return 1;
            }
        }
    );

};

$twitter_loop->(qq( [info] start to listen "twitter_listener"));


if (my $error_message = $cv->recv) {
    die $error_message;
}


sub reply {
    my $tweet    = shift;
    my $on_error = shift || sub {
        my $error_message = shift;
        $log_dispatcher->error(get_now() . qq( [error] ${error_message} "in reply"));
    };

    my @has_lunch_shop_ids = grep{ ref $tabelog_data{$_}->{LunchPrice} ne 'HASH' }(keys %tabelog_data);

    my $help = sub {
        my $c = int rand @has_lunch_shop_ids;
        my $shop = $tabelog_data{$has_lunch_shop_ids[$c]};
        "\@$tweet->{user}{screen_name} $shop->{Category} 『$shop->{RestaurantName}』 via 食べログ $shop->{LunchPrice} $shop->{TabelogMobileUrl}";
    };

    my $reply = $help->();
    while ($before_tweet eq $reply) {
        $reply = $help->();
    }
    $before_tweet = $reply;

    tweet($reply, $tweet->{id}, $on_error);
}

sub qt {
    my $tweet    = shift;
    my $on_error = shift || sub {
        my $error_message = shift;
        $log_dispatcher->error(get_now() . qq( [error] ${error_message} "in QT"));
    };
    my $re_tweet = "QT: !$tweet->{user}{screen_name} $tweet->{text}";

    $re_tweet =~ s/@/!/g;
    $re_tweet = substr($re_tweet, 0, 136) . ' ...' if length $re_tweet > 140;

    if ($before_tweet eq $re_tweet) {
        $log_dispatcher->warning(get_now() . qq( [warn] ! not tweet "${re_tweet}" because it is same as before tweet));
        return;
    }
    $before_tweet = $re_tweet;

    tweet($re_tweet, $on_error);
}

sub tweet {
    my $new_tweet   = shift;
    my $on_error    = pop;
    my $in_reply_to = shift;

    my $help; $help = sub {
        $twitter_client->post('statuses/update', {
                status => $new_tweet,
                ($in_reply_to
                    ? ('in_reply_to_status_id' => $in_reply_to) 
                    : ()
                )
            }, sub {
                my ($header, $response, $reason) = @_;
                unless ($response) {
                    $on_error->(qq($header->{Status} $reason));
                    if ($header->{Status} ne '403') {
                        my $t; $t = AE::timer 3, 0, sub {
                            undef $t;
                            $help->();
                            return;
                        };
                    }
                }

                $log_dispatcher->info(get_now() . encode_utf8 qq( [info] post "${new_tweet}" "twitter_client"));
            }
        );
    };

    $help->();
}

sub get_lunch_shop_ids {
    unless (%tabelog_data) {
        $log_dispatcher->error(get_now() . qq( [error] !! "tabelog_data" empty));
        my $t; $t = AE::timer 0, 0, sub {
            $log_dispatcher->info(get_now() . qq( [info] retry get "tabelog_data"));
            undef $t;
            $get_tabelog_data->();
        };
    }

    grep{ ref $tabelog_data{$_}->{LunchPrice} ne 'HASH' }(keys %tabelog_data);
}
sub log_dispatcher_new {
    local $_       = shift;
    my $dispatcher = Log::Dispatch->new;

    $_->{dispatch_file}{filename} = $_->{dir} . '/' . get_now() . '.log';

    $dispatcher->add(Log::Dispatch::File->new(%{$_->{dispatch_file}}));
    $dispatcher->add(Log::Dispatch::Screen->new(%{$_->{dispatch_screen}}));
    $dispatcher;
}
sub get_now {
    my $now = shift || (sub {
        AE::now_update;
        AE::now;
    })->();

    my($sec, $min, $hour, $day, $month, $year, @und) = localtime $now;
    return sprintf "%d-%02d-%02d_%02d:%02d:%02d", $year+1900, $month+1, $day, $hour, $min, $sec;
}

sub read_keyword {
    my $keyword_pl = shift;
    die qq('${keyword_pl}' not found) unless -e $keyword_pl;

    local $_ = do $keyword_pl;

    die qq(not defined '$_') unless defined $_;

    $twitter_lunch_regexp = $_;

    return 1;
}
__END__

