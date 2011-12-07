package AnyEvent::Tabelog::Search;
use strict;
use utf8;
use Carp;
use URI;
use AnyEvent;
use AnyEvent::HTTP qw(http_request);
use XML::Simple;

our $VERSION  = '0.02';
my  $api_mode = 'RestaurantSearch';

sub new {
    my $class   = shift;
    my $api_key = shift || Carp::croak qq(! failed: 1st argument-- "api_key" not found\n);

    bless { api_key => $api_key }, $class;
}

sub get {
    my $self     = shift;
    my $callback = pop || Carp::croak qq(! failed: "callback" not found\n);
    my %args     = @_;

    my $mode = delete $args{mode} || $api_mode;

    Carp::croak '! failed: "mode" is wrong( or not found)' unless $mode =~ /^(RestaurantSearch|ReviewSearch|ReviewImageSearch)$/;

    my $api_uri = _get_api_uri($mode);
    my $uri     = URI->new("${api_uri}${mode}/");

    my $on_error  = delete $args{on_error}  || sub { die @_; return };
    my $on_header = delete $args{on_header} || sub {
        my $headers = shift;
        unless ($headers->{Status} =~ /^2/) {
            $on_error->(qq(! failed: $headers->{Status} $headers->{Reason}\n));
            return ;
        }
        return 1;
    };

    $args{Key} = $self->{api_key};
    $uri->query_form( %args );

    my $g; $g = http_request( 'GET' => $uri->as_string,
        on_header => $on_header,
        sub {
            undef $g;
            my($data, $headers) = @_;
            $callback->(XMLin($data), $headers);
        }
    );

}

sub _get_api_uri {
    my $mode     = shift;
    my $api_uri  = 'http://api.tabelog.com';

    ($mode eq 'RestaurantSearch')
        ? "${api_uri}/Ver2.1/"
        : "${api_uri}/Ver1/"
    ;
}

1;

__END__

=head1 NAME

AnyEvent::Tabelog::Search - a interface to get informations from Tabelog API, based on AnyEvent.


=head1 SYNOPSIS

  use AnyEvent;
  use AnyEvent::Tabelog::Search;
  use Encode;

  my $api_key = '....'; # see also http://tabelog.com/help/api/
  my $tablog  = AnyEvent::Tabelog::Search->new( $api_key );
  
  my $cv = AE::cv;
  
  for my $page (1..3) {
      $cv->begin;
      $tabelog->get(
          mode  => 'RestaurantSearch', # or 'ReviewSearch', 'ReviewImageSearch'
          Latitude    => '37.115147',
          Longitude   => '138.242209',
          SearchRange => 'medium',
          PageNum     => $page,
          on_error    => sub {
              my $headers = shift;
              $cv->send("! failed: $headers->{Status} $headers->{Reason}");
          },
          sub {
              my($data, $headers) = @_;
              for my $shop (@{$data->{Item}}) {
                  print encode_utf8($shop->{RestaurantName}), "\m";
              }
              $cv->end;
          }
      );
  }
  
  $cv->recv;


=head1 DESCRIPTION

get some informations form Tabelog API, based on AnyEvent.
using Tabelog API is required "access key". see also L<http://tabelog.com/help/api/>


=head1 METHOD

=head2 my $tablog = AnyEvent::Tabelog::Search->new($api_key);

B<$api_key> is "access key". this paramater is required.


=head2 $tabelog->get(%args, $callback);

=item B<mode>

"mode" is required.

=over 2

=item B<RestaurantSearch> http://api.tabelog.com/Ver2.1/RestaurantSearch/?...

=item B<ReviewSearch> http://api.tabelog.com/Ver1/ReviewSearch/?... 

=item B<ReviewImageSearch> http://api.tabelog.com/Ver1/ReviewImageSearch/?...


=back

=head1 SEE ALSO

L<http://tabelog.com/help/api/>, L<http://tabelog.com/help/api_manual>


=cut

