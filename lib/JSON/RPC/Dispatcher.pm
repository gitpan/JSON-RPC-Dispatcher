package JSON::RPC::Dispatcher;
our $VERSION = '0.0400';

=head1 NAME

JSON::RPC::Dispatcher - A JSON-RPC 2.0 server.

=head1 VERSION

version 0.0400

=head1 SYNOPSIS

In F<app.psgi>:

 use JSON::RPC::Dispatcher;

 my $rpc = JSON::RPC::Dispatcher->new;

 sub add_em {
    my @params = @_;
    my $sum = 0;
    $sum += $_ for @params;
    return $sum;
 }
 $rpc->register( 'sum', \&add_em );

 $rpc->to_app;

Then run it:

 plackup app.psgi

Now you can then call this service via a GET like:

 http://example.com/?method=sum;params=[2,3,5];id=1

Or by posting JSON to it like this:

 {"jsonrpc":"2.0","method":"sum","params":[2,3,5],"id":"1"}

And you'd get back:

 {"jsonrpc":"2.0","result":10,"id":"1"}
 
=head1 DESCRIPTION

Using this app you can make any PSGI/L<Plack> aware server a JSON-RPC 2.0 server. This will allow you to expose your custom functionality as a web service in a relatiely tiny amount of code, as you can see above.

This module follows the draft specficiation for JSON-RPC 2.0. More information can be found at L<http://groups.google.com/group/json-rpc/web/json-rpc-1-2-proposal>.

=head2 Advanced Error Handling

You can also throw error messages rather than just C<die>ing, which will throw an internal server error. To throw a specific type of error, C<die>, C<carp>, or C<confess>, an array reference starting with the error code, then the error message, and finally ending with error data (optional). When JSON::RPC::Dispatcher detects this, it will throw that specific error message rather than a standard internal server error.

 use JSON::RPC::Dispatcher;
 my $rpc = JSON::RPC::Dispatcher->new;

 sub guess {
     my ($guess) = @_;
    if ($guess == 10) {
	    return 'Correct!';
    }
    elsif ($guess > 10) {
        die [986, 'Too high.'];
    }
    else {
        die [987, 'Too low.'];
    }
 }

 $rpc->register( 'guess', \&guess );

 $rpc->to_app;

B<NOTE:> If you don't care about setting error codes and just want to set an error message, you can simply C<die> in your RPC and your die message will be inserted into the C<error_data> method.

=head2 Logging

JSON::RPC::Dispatcher allows for logging via L<Log::Any>. This way you can set up logs with L<Log::Dispatch>, L<Log::Log4perl>, or any other logging system that L<Log::Any> supports now or in the future. It's relatively easy to set up. In your F<app.psgi> simply add a block like this:

 use Log::Any::Adapter;
 use Log::Log4perl;
 Log::Log4perl::init('/path/to/log4perl.conf');
 Log::Any::Adapter->set('Log::Log4perl');

That's how easy it is to start logging. You'll of course still need to configure the F<log4perl.conf> file, which goes well beyond the scope of this document. And you'll also need to install L<Log::Any::Adapter::Log4perl> to use this example.

=cut


use Moose;
use bytes;
extends qw(Plack::Component);
use Plack::Request;
use JSON;
use JSON::RPC::Dispatcher::Procedure;
use Log::Any qw($log);

#--------------------------------------------------------
has error_code => (
    is          => 'rw',
    default     => undef,
    predicate   => 'has_error_code',
);

#--------------------------------------------------------
has error_message => (
    is      => 'rw',
    default => undef,
);

#--------------------------------------------------------
has error_data  => (
    is      => 'rw',
    default => undef,
);

#--------------------------------------------------------
has rpcs => (
    is      => 'rw',
    default => sub { {} },
);

#--------------------------------------------------------
sub register {
    my ($self, $name, $sub) = @_;
    my $rpcs = $self->rpcs;
    $rpcs->{$name} = $sub;
    $self->rpcs($rpcs);
}

#--------------------------------------------------------
sub acquire_procedures {
    my ($self, $request) = @_;
    if ($request->method eq 'POST') {
        return $self->acquire_procedures_from_post($request->content);
    }
    elsif ($request->method eq 'GET') {
        return [ $self->acquire_procedure_from_get($request->query_parameters) ];
    }
    else {
        $self->error_code(-32600);
        $self->error_message('Invalid Request.');
        $self->error_data('Invalid method type: '.$request->method);
        return [];
    }
}

#--------------------------------------------------------
sub acquire_procedures_from_post {
    my ($self, $body) = @_;
    my $request = eval{from_json($body)};
    if ($@) {
        $self->error_code(-32700);
        $self->error_message('Parse error.');
        $self->error_data($body);
        return undef;
    }
    else {
        if (ref $request eq 'ARRAY') {
            my @procs;
            foreach my $proc (@{$request}) {
                push @procs, $self->acquire_procedure_from_hashref($proc);
            }
            return \@procs;
        }
        elsif (ref $request eq 'HASH') {
            return [ $self->acquire_procedure_from_hashref($request) ];
        }
        else {
            $self->error_code(-32600);
            $self->error_message('Invalid request.');
            $self->error_data($request);
            return undef;
        }
    }
}

#--------------------------------------------------------
sub acquire_procedure_from_hashref {
    my ($self, $hashref) = @_;
    my $proc = JSON::RPC::Dispatcher::Procedure->new;
    $proc->method($hashref->{method});
    $proc->id($hashref->{id});
    $proc->params($hashref->{params}) if exists $hashref->{params};
    return $proc;
}

#--------------------------------------------------------
sub acquire_procedure_from_get {
    my ($self, $params) = @_;
    my $proc = JSON::RPC::Dispatcher::Procedure->new;
    $proc->method($params->{method});
    $proc->id($params->{id});
    my $decoded_params = (exists $params->{params}) ? eval{from_json($params->{params})} : undef;
    if ($@) {
        $proc->error_code(-32602);
        $proc->error_message('Invalid params');
        $proc->error_data($params->{params});
    }
    else {
        $proc->params($decoded_params) if defined $decoded_params;
    }
    return $proc;
}

#--------------------------------------------------------
sub translate_error_code_to_status {
    my ($self, $code) = @_;
    $code ||= '';
    my %trans = (
        ''          => 200,
        '-32600'    => 400,
        '-32601'    => 404,
    );
    my $status = $trans{$code};
    $status ||= 500;
    return $status;
}

#--------------------------------------------------------
sub handle_procedures {
    my ($self, $procs) = @_;
    my @responses;
    my $rpcs = $self->rpcs;
    foreach my $proc (@{$procs}) {
        my $is_notification = (defined $proc->id && $proc->id ne '') ? 0 : 1;
        unless ($proc->has_error_code) {
            my $rpc = $rpcs->{$proc->method};
            if (defined $rpc) {
                my $result;

                # deal with params and calling
                my $params = $proc->params;
                if (ref $params eq 'HASH') {
                    $result = eval{$rpc->(%{$params})};
                }
                elsif (ref $params eq 'ARRAY') {
                    $result = eval{$rpc->(@{$params})};
                }
                else {
                    $result = eval{$rpc->()};
                }

                # deal with result
                if ($@ && ref($@) eq 'ARRAY') {
                    $proc->error(@{$@});
                    $log->error($@->[1]);
                    $log->debug($@->[2]);
                }
                elsif ($@) {
                    my $error = $@;
                    if ($error->can('error') && $error->can('trace')) {
                         $error = $error->error;
                         $log->fatal($error->error);
                         $log->trace($error->trace->as_string);
                    }
                    elsif ($error->can('error')) {
                        $error = $error->error;
                        $log->fatal($error);
                    }
                    elsif (ref $error ne '' && ref $error ne 'HASH' && ref $error ne 'ARRAY') {
                        $log->fatal($error);
                        $error = ref $error;
                    }
                    $proc->internal_error($error);
                }
                else {
                    $proc->result($result);
                }
            }
            else {
                $proc->method_not_found($proc->method);
            }
        }

        # remove not needed elements per section 5 of the spec
        my $response = $proc->response;
        if (exists $response->{error}{code}) {
            delete $response->{result};
        }
        else {
            delete $response->{error};
        }

        # remove responses on notifications per section 4.1 of the spec
        unless ($is_notification) {
            push @responses, $response;
        }
    }

    # return the appropriate response, for batch or not
    if (scalar(@responses) > 1) {
        return \@responses;
    }
    else {
        return $responses[0];
    }
}

#--------------------------------------------------------
sub call {
    my ($self, $env) = @_;

    my $request = Plack::Request->new($env);
    $log->info("REQUEST: ".$request->content) if $log->is_info;
    my $procs = $self->acquire_procedures($request);

    my $rpc_response;
    if ($self->has_error_code) {
        $rpc_response = { 
            jsonrpc => '2.0',
            error   => {
                code    => $self->error_code,
                message => $self->error_message,
                data    => $self->error_data,
            },
        };
    }
    else {
        $rpc_response = $self->handle_procedures($procs);
    }

    my $response = $request->new_response;
    if ($rpc_response) {
        my $json = eval{to_json($rpc_response)};
        if ($@) {
            $log->warn("JSON repsonse error: ".$@);
            $json = to_json({
                jsonrpc => "2.0",
                error   => {
                    code    => -32099,
                    message => "Couldn't convert method response to JSON.",
                    data    => $@,
                    }
                 });
        }
        $response->status($self->translate_error_code_to_status( (ref $rpc_response eq 'HASH' && exists $rpc_response->{error}) ? $rpc_response->{error}{code} : '' ));
        $response->content_type('application/json-rpc');
        $response->content_length(bytes::length($json));
        $response->body($json);
        $log->info("RESPONSE: ".$response->body) if $log->is_info;
    }
    else { # is a notification only request
        $response->status(204);
        $log->info('RESPONSE: Notification Only');
    }
    return $response->finalize;
}

=head1 PREREQS

L<Moose> 
L<JSON> 
L<Plack>
L<Test::More>
L<Log::Any>

=head1 TODO

Once the JSON-RPC 2.0 spec is finalized, this module may need to change to support any last minute changes or additions.

=head1 SUPPORT

=over

=item Repository

L<http://github.com/plainblack/JSON-RPC-Dispatcher>

=item Bug Reports

L<http://rt.cpan.org/Public/Dist/Display.html?Name=JSON-RPC-Dispatcher>

=back

=head1 SEE ALSO

You may also want to check out these other modules, especially if you're looking for something that works with JSON-RPC 1.x.

=over 

=item Dispatchers

Other modules that compete directly with this module, though perhaps on other protocol versions.

=over

=item L<JSON::RPC>

An excellent and fully featured both client and server for JSON-RPC 1.1.

=item L<POE::Component::Server::JSONRPC>

A JSON-RPC 1.0 server for POE. I couldn't get it to work, and it doesn't look like it's maintained.

=item L<Catalyst::Plugin::Server::JSONRPC>

A JSON-RPC 1.1 dispatcher for Catalyst.

=item L<CGI-JSONRPC>

A CGI/Apache based JSON-RPC 1.1 dispatcher. Looks to be abandoned in alpha state. Also includes L<Apache2::JSONRPC>.

=item L<AnyEvent::JSONRPC::Lite>

An L<AnyEvent> JSON-RPC 1.x dispatcher. 

=item L<Sledge::Plugin::JSONRPC>

JSON-RPC 1.0 dispatcher for Sledge MVC framework.

=back

=item Clients

Modules that you'd use to access various dispatchers.

=over

=item L<JSON::RPC::Common>

A JSON-RPC client for 1.0, 1.1, and 2.0. Haven't used it, but looks pretty feature complete.

=item L<RPC::JSON>

A simple and good looking JSON::RPC 1.x client. I haven't tried it though.

=back

=back

=head1 AUTHOR

JT Smith <jt_at_plainblack_com>

=head1 LEGAL

JSON::RPC::Dispatcher is Copyright 2009-2010 Plain Black Corporation (L<http://www.plainblack.com/>) and is licensed under the same terms as Perl itself.

=cut

1;