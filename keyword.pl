use strict;
use utf8;

my $keywords = qr(
    lunch|ランチ|らんち|
    hirumes[h]?i|((ヒル|ひる|昼)|(メシ|めし|飯))|
    hirugohan[n]?|((ヒル|ひる|昼)|(ゴ|ご|御)?(ハン|はん|飯))|
    (昼(.)*食)
)xi;

