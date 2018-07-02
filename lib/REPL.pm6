
use Readline;
use Getopt::Advance;

unit module REPL;

has %!cmds;
has %!callbacks;
has %.data is rw;
has $.optionset;
has $.stdout;
has $.stderr;
has &.helper;
has $.flag;
has $!rl;

constant CMD is export = my method (OptionSet $os, @args) { True; };

sub repl-help($optset, $outfh) {
    my %no-cmd = $optset.get-cmd();
    my %no-pos = $optset.get-pos();
    my @main = $optset.values();
    my (@command, @front, @pos, @wepos, @opts) := ([], [], [], [], []);

    if %no-cmd.elems > 0 {
        @command.push($_) for %no-cmd.values>>.usage;
    }

    if %no-pos.elems > 0 {
        my $fake = 4096;
        my %kind = classify {
            $_.index ~~ Int ?? ($_.index == 0 ?? 0 !! 'index' ) !! '-1'
        }, %no-pos.values;

        if %kind{0}:exists && %kind<0>.elems > 0 {
            @front.push("<{$_}>") for @(%kind<0>)>>.usage;
        }

        if %kind<index>:exists && %kind<index>.elems > 0 {
            my %pos = classify { $_.index }, @(%kind<index>);

            for %pos.sort(*.key)>>.value -> $value {
                @pos.push("<{join("|", @($value)>>.usage)}>");
            }
        }

        if %kind{-1}:exists && %kind{-1}.elems > 0 {
            my %pos = classify { $_.index.($fake) }, @(%kind{-1});

            for %pos.sort(*.key)>>.value -> $value {
                @wepos.push("<{join("|", @($value)>>.usage)}>");
            }
        }
    }
    for @main -> $opt {
        @opts.push($opt.optional ?? "[{$opt.usage}]" !! "<{$opt.usage}>");
    }

    my $usage = "";

    $usage ~= '[' if +@command > 1 || +@front > 1 || (+@command > 0 && +@front > 0);
    $usage ~= @command.join("|") if +@command > 0;
    $usage ~= '|' if +@command > 0 && +@front > 0;
    $usage ~= @front.join("|") if +@front > 0;
    $usage ~= ']' if +@command > 1 || +@front > 1 || (+@command > 0 && +@front > 0);
    $usage ~= " {join(" ", @pos)} ";
    $usage ~= "{join(" ", @opts)} {join(" ", @wepos)} ";

    my @annotations = [];

    @annotations.push("{.join(" ")}\n") for @($optset.annotation());

    ($usage, @annotations);
}

sub printHelp($os, $outfh = $*OUT) {
    my ($usage, @annotations) := &repl-help($os, $outfh);

    $outfh.say($usage);
    $outfh.say("");
    $outfh.say($_) for @annotations;
}

sub defaultOptionSet() {
    my OptionSet $os .= new;
    $os.push(
        'h|help=b',
        'print the help message.'
    );
    $os;
}

method new(
    :%data,
    :$optionset = defaultOptionSet(),
    :$stdout = $*OUT,
    :$stderr = $*ERR,
    :&helper = &printHelp,
) {
    self.bless(:%data, :$optionset, :$stdout, :$stderr, :&helper);
}

submethod TWEAK() {
    $!rl = Readline.new;
    $!rl.using-history();
    if (&!helper.defined) {
        self.push(
            "help",
            my method (OptionSet $os, @args) {
                if +@args == 0 {
                    self.stderr.say(%!cmds.keys.join(" "));
                } else {
                    if +@args == 1 {
                        &!helper(self.get(@args[0].value), self.stderr);
                        return True;
                    } 
                    return False;
                }
            }
        );
    }
}

method !create-main-sub(&cb) {
    return sub ($os, @args) {
        @args.shift if +@args >= 1;
        if !$os<h> && &cb(self, $os, @args) != False {
            return;
        }
        &!helper($os, self.stderr) if &!helper.defined;
    };
}

multi method push(Str $cmd, &cb:(Mu: OptionSet, @, *%_)) {
    %!cmds{$cmd} = do {
        my $os = $!optionset.clone;
        $os.insert-cmd($cmd);
        $os.insert-main(self!create-main-sub(&cb));
        $os;
    }
    %!callbacks{$cmd} = &cb;
}

multi method push(Str $cmd, &cb:(Mu: OptionSet, @, *%_), &tweak:(Mu: OptionSet, *%_)) {
    %!cmds{$cmd} = do {
        my $os = $!optionset.clone;
        &tweak(self, $os) if &tweak.defined;
        $os.insert-cmd($cmd);
        $os.insert-main(self!create-main-sub(&cb));
        $os;
    }
    %!callbacks{$cmd} = &cb;
}

multi method push(Str $cmd, OptionSet $os) {
    %!cmds{$cmd} = $os;
}

method get(Str $cmd --> OptionSet) {
    %!cmds{$cmd};
}

method alias(Str $from, Str $to) {
    %!cmds{$to} := %!cmds{$from};
    %!callbacks{$to} := %!callbacks{$from};
}

method find(Str $cmd) {
    %!callbacks{$cmd};
}

method do(Str $cmd, *@args) {
    getopt([ $cmd, | @args ], %!cmds.values, :autohv, :&!helper);
}

method run(Str $prompt = ">>") {
    $!flag = True;
    while $!flag {
        if $!rl.readline($prompt) -> $line {
            if $line.trim -> $line {
                $!rl.add-history($line);
                try {
                    getopt($line.split(/\s+/, :skip-empty), %!cmds.values, :autohv, :&!helper);
                    CATCH {
                        default {
                            say "not recognize command: $line";
                        }
                    }
                }
            }
        }
    }
}