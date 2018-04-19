#! /usr/bin/env perl
# file: App/Devel/Todo.pm
# author: Adam Marshall (ih8celery)
# brief: definitions of todo utility functions

package App::Devel::Todo;

use strict;
use warnings;

BEGIN {
  use Exporter;

  our @ISA = qw/Exporter/;
  our @EXPORT = qw/&run/;
}

use Devel::Todo;

use feature qw/say/;

use Getopt::Long;
use Cwd qw/getcwd/;
use File::Basename;
use YAML::XS qw/LoadFile/;

# config variables always relevant to the program
our $VERSION      = '0.05';
our $CONFIG_FILE  = "$ENV{HOME}/.todorc.yml";
our $TODO_FILE    = '';

# the general action which will be taken by the program
our $ACTION = $Action::CREATE;

# status selected by the subcommand
our $STATUS = 'do';

# default attributes
our $DEFAULT_STATUS      = 'do';
our $DEFAULT_PRIORITY    = 0;
our $DEFAULT_DESCRIPTION = '';

# attributes given on the command line
our $STATUS_OPT;
our $PRIORITY_OPT;
our $DESCRIPTION_OPT;

# before creating a new todo, an old one that matches may be moved
our $MOVE_ENABLED = 1;

# controls whether a help message will be printed for subcommand
our $HELP_REQUESTED = 0;

# options are case-sensitive
Getopt::Long::Configure('no_ignore_case');

# declare command-line options
our %OPTS = (
  'help|h'              => sub { $HELP_REQUESTED = 1; },
  'version|v'           => \&_version,
  'delete|D'            => sub { $ACTION = $Action::DELETE; },
  'create|C'            => sub { $ACTION = $Action::CREATE; },
  'edit|E'              => sub { $ACTION = $Action::EDIT; },
  'show|S'              => sub { $ACTION = $Action::SHOW; },
  'create-no-move|N'    => sub { $ACTION = $Action::CREATE; $MOVE_ENABLED = 0; },
  'config-file|f=s'     => \$CONFIG_FILE,
  'todo-file|t=s'       => \$TODO_FILE,
  'use-status|s=s'      => \$STATUS_OPT,
  'use-priority|p=s'    => \$PRIORITY_OPT,
  'use-description|d=s' => \$DESCRIPTION_OPT
);

our %STATUSES = (
  all  => 'selects every item regardless of status',
  do   => 'selects list of todos',
  did  => 'selects list of finished items',
  want => 'selects list of goals'
);

# print a help message appropriate to the situation and exit
sub _help {
  my $h_type = shift || 's';
  my $h_general_help = <<EOM;
Options:
-h|--help              print help
-v|--version           print application version information
-S|--show              print item/s from the currently selected list
-E|--edit              change list item information
-C|--create            add new item/s to selected list or move from another list
-N|--create-no-move    add new item/s to selected list without moving
-D|--delete            remove item/s from selected list
-f|--config-file=s     set global configuration file
-t|--todo-file=s       set project file
-s|--use-status=s      set the status used by some actions
-p|--use-priority=s    set the priority used by some actions
-d|--use-description=s set the description used by some actions 
EOM

  if ($h_type eq 'a') {
    say $h_general_help;
  }
  else {
    say $STATUSES{$STATUS};
  }

  exit 0;
}

# print the application name and version number and exit
sub _version {
  say "todo $VERSION";

  exit 0;
}

# auxiliary function to collect the subcommand
sub get_possible_subcommand {
  my $gs_num_args = scalar @ARGV;
  my $gs_STATUS;

  if ($gs_num_args == 0) {
    _help('a');
  }
  else {
    if ($ARGV[0] eq '-v' || $ARGV[0] eq '--version') {
      _version();
    }
    elsif ($ARGV[0] eq '-h' || $ARGV[0] eq '--help') {
      _help('a');
    }
    elsif ($ARGV[0] =~ m/\w[\w\-\+\.\/]*/) {
      $gs_STATUS = $ARGV[0];
    }
    else {
      die("expected subcommand or global option");
    }
  }

  if ($gs_num_args == 1) {
    $ACTION = $Action::SHOW;
  }

  return $gs_STATUS;
}

# process non-option arguments into a list of keys and values
sub process_args {
  my @pa_out  = ();

  my $pa_key   = "";
  my $pa_blob  = [];
  my $pa_count = 0;
  foreach (@ARGV) {
    # arg is form 'key.'
    # finish with current hash, if any, and initialize a new one
    if (m/^\s*(.+?)\.\s*$/) {
      push @pa_out, [$pa_key, $pa_blob] if $pa_count;

      $pa_key   = $1;
      $pa_blob  = [];
      $pa_count = 0;

      next;
    }

    # arg is form 'key.val'
    # reset $key and add current hash unless empty and add a pair
    if (m/^\s*(.+?)\.(.+)\s*$/) {
      if ($pa_key ne $1) {
        push @pa_out, [$pa_key, $pa_blob] if $pa_count;
      }
      
      $pa_key   = "";
      $pa_blob  = [];
      $pa_count = 0;

      push @pa_out, [$1, [$2] ];

      next;
    }

    # arg is form 'val'
    # if $key is "", push to list; else add to current blob 
    if (m/^\s*([^\.]+)\s*$/) {
      if ($pa_key eq "") {
        push @pa_out, $1;
      }
      else {
        $pa_count++;

        push @$pa_blob, $1;
      }

      next;
    }

    die("arg $_ is invalid");
  }

  if ($pa_count) {
    push @pa_out, [$pa_key, $pa_blob];
  }

  return @pa_out;
}

# load the global configuration file settings
# TODO
sub configure_app {
  my ($ca_file) = @_;
  die('config file not found') unless -f $ca_file;

  my $ca_settings = LoadFile($ca_file);
  
  # create new statuses, if any
  if (defined $ca_settings->{statuses}) {
    foreach (keys %{ $ca_settings->{statuses} }) {
      if ($_ =~ m/\w[\w\-\+\.\/]*/ && !exists($STATUSES{$_})) {
        if (ref $ca_settings->{statuses}{$_} eq '') {
          $STATUSES{$_} = $ca_settings->{statuses}{$_};
        }
        else {
          die('new status must be created with a help message');
        }
      }
      else {
        die('new status must match \'\\w[\\w\\-\\+\\.\\/]*\' and not already exist');
      }
    }
  }

  # set defaults, if any
}

# search recursively upward from the current directory for todos
# until any project or the home directory is found
sub find_project {
  my $fp_dir = getcwd;
  my $fp_file = $fp_dir . '/' . '.todos';

  if ($fp_dir !~ /^$ENV{HOME}/) {
    $fp_dir = $ENV{HOME};
  }
  elsif ($fp_dir ne $ENV{HOME}) {
    until ($fp_dir eq $ENV{HOME}) {
      last if -f $fp_file;

      $fp_dir  = dirname $fp_dir;
      $fp_file = $fp_dir . '/' . '.todos';
    }
  }
  
  die('no project file found') unless (-f $fp_file);

  return $fp_file;
}

# main application logic
sub run {
  my ($r_STATUS, $r_project_file, $r_todos);
  my @r_args;

  # the possible subcommand retrieved here will be verified
  # after the config file has been processed, since status/
  # subcommand may be defined there
  $r_STATUS = get_possible_subcommand();
  shift @ARGV;

  exit 1 unless GetOptions(%OPTS);

  # reads the configuration file, sets new app defaults if any
  # defined, and creates new subcommands/statuses. if any of the
  # latter are invalid for some reason, they will be ignored
  configure_app($CONFIG_FILE);

  # verify the possible subcommand
  if (exists $STATUSES{$r_STATUS}) {
    $STATUS = $r_STATUS;
  }
  else {
    die("unknown subcommand: $r_STATUS");
  }

  $DEFAULT_STATUS = $STATUS unless ($STATUS eq 'all');
  
  # prints help for subcommand
  # this function is called here because not all subcommands
  # may be known until after the app is configured
  _help('s') if $HELP_REQUESTED;

  # processes remaining command-line arguments into keys and values
  # so that it is clear which parts of the 'lists' will be affected
  @r_args = process_args();

  $r_project_file = find_project();

  $r_todos = LoadFile($r_project_file);

  if ($ACTION == $Action::CREATE) {
    create_stuff($r_project_file, $r_todos, \@r_args);
  }
  elsif ($ACTION == $Action::SHOW) {
    show_stuff($r_todos, \@r_args);
  }
  elsif ($ACTION == $Action::EDIT) {
    edit_stuff($r_project_file, $r_todos, \@r_args);
  }
  elsif ($ACTION == $Action::DELETE) {
    delete_stuff($r_project_file, $r_todos, \@r_args);
  }
}

__END__

=head1 Name

todo -- manage your todo list

  todo [global options] [subcommand] [options] [arguments]

=head1 Summary

C<todo> helps you manage your todo list. your list is a YAML file, which
does not really contain a list, but a hash table. your list is composed
of items. an item has a name, which is the key to the hash table, and at
least one attribute, its status. see the example below.

  ---
  name: today
  contents:
    wake: did
    eat: want
    sleep: do
    code:
      status: do
  ...

the above yaml snippet shows two ways to set the status: as the value of
the item in the document's B<contents> hash; and as the value of the
key below the item. either approach is valid. note that in any case,
every item B<must> be assigned a status. status is a way of describing
the current condition of an item. by default, you may choose from three
statuses: "do", "did", and "want". incidentally, the "subcommand" you
use corresponds to the status of the items you want to create, see,
delete, or edit.

the status is one of three possible attributes that an item may have.
unlike the status attribute, these attributes need not be present in an item.
the other two attributes are priority, a positive integer, and description.
a priority of zero is the default and is the 'first' priority, much as
zero is the first index of arrays in most programming languages. the
description is simply a string which should be used to clarify the
meaning of an item.

items may contain an additional member: contents. the presence of this
key indicates that an item is a todo list in its own right. such a
sublist may contain items just like its parent, with one exception:
further sublists. 

  ---
  name: tomorrow
  contents:
    wake: do
    eat: want
    other:
      status: do
      contents:
        walk my dog: do
        sacrifice to Odin: do
  ...

notice that both the parent todo list and its sublist 'other' have a
I<contents> key. the contents key is required for a list to be
recognized.

=head1 Subcommands

before you ask, the subcommands are not in fact "commands"; the actual
commands reside among the regular options. you may attribute this mangling
of convention to three lines of reasoning: first, I believed that the order
of command-line arguments should correspond to how I formulate a todo in
my own mind. I think first that I should B<do> foo, not B<add> foo to
the list of items that I must do. secondly, I found that using status
instead of true commands better facilitated my two most common use
cases: looking at everything in a list with a particular status, and
adding a new item somewhere. for comparison, 

  todo do     # shows everything with "do" status
  todo do foo # adds a new item called foo with "do" status

allows me to differentiate between showing and adding items simply by
the presence or absence of additional arguments. but

  todo show --do
  todo add --do foo

requires an extra piece of information in most cases (if "do" were the
default status we could shorten this example by removing C<--do>,
but this still leaves the other statuses. finally, I wanted to allow
users to define new statuses particular to how they work, which would
be easier to support if the status had to appear as the first argument
to C<todo>.

NOTE: except for 'all', the subcommand sets the default status used by the
program

the following subcommands are automatically defined:

=over 4

=item do

select items with "do" status

=item did

select items with "did" status

=item want

select items with "want" status

=item all

select everything, regardless of status. this subcommand cannot be
used in combination with creating or editing items

=back

=head1 General Options

=over 4

=item -h|--help

print help. if this option is supplied first, general help concerning
the options is printed. otherwise, it will print help for the current
subcommand

=item -v|--version

print application version information

=item -S|--show

print item/s from the currently selected list

=item -E|--edit

change list item information

=item -C|--create

add new item/s to selected list or move from another list

=item -N|--create-no-move

add new item/s to selected list without the possibility of moving
from another list

=item -D|--delete

remove item/s from selected list. 

=item -s|--use-status

specify a status. this is relevant when creating or editing items,
and it is different from the status set by the subcommand

=item -d|--use-description

specify a description. this is relevant when creating or editing items

=item -p|--use-priority

specify a priority. this is relevant when creating or editing items

=item -f|--config-file

specify a different file to use as configuration file

=item -t|--todo-file

specify a different file to use as project todo list

=back

=head1 Arguments

arguments are used to identify items and groups of items. there are
three types of arguments:

=over 4

=item keys

Example: vim.

to be a key, an argument string must end on a '.'
a key starts a new sublist named after the key to which 
values will be added

=item values

Example: "read vim-perl help"

to be a value, an argument must simply not contain a '.'.
added to the list or a sublist, if one is active. add a description
to a value by following it with '='

=item key-value pairs

examples: vim."read vim-perl help", vim.perl="read vim-perl help"

a key-value pair is a string with two parts separated by a '.'
adds to a sublist named after the key, creating the sublist if it does
not exist. add a description to a value by following it with '='

=back

=head1 Examples

todo do "eat something"

todo do "eat something" "walk the dog"

todo do exercise

todo do todo-app. "implement create" "implement delete" "implement show"

todo want -S

todo do -D todo-app."implement show"

=head1 Copyright and License

Copyright (C) 2018 Adam Marshall.
This software is distributed under the MIT License

=cut

