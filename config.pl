sub config {
    +{
        log => {
            dir => './log',
            dispatch_file => {
                name      => 'file1',
                min_level => 'debug',
                filename  => , # get_now()
                mode      => 'append',
                newline   => 1
            },
            dispatch_screen => {
                name      => 'screen1',
                min_level => 'debug',
                stderr    => 1,
                newline   => 1
            },
        },
        tabelog => {
            api_key => '', #YOUR TABELOG API KEY
            request => {
                mode        => '',
                Latitude    => '',
                Longitude   => '',
                SearchRange => '',
            }
        },
        twitter_bot => {
            id    => '', #YOUR TWITTER BOT ID
            oauth => {
                consumer_key    => '',
                consumer_secret => '',
                token           => '',
                token_secret    => ''
            }
        }
    };
}


1;

