my class Exception { ... }


my class Backtrace is List {
    class Frame {
        has Str $.file;
        has Int $.line;
        has Mu  $.code;
        has Str $.subname;

        method subtype {
            my $s = $!code.WHAT.perl.lc;
            $s eq 'mu' ?? '' !! $s;
        }

        multi method Str(Backtrace::Frame:D:) {
            my $s = $.subtype;
            $s ~= ' ' if $s.chars;
            "  in {$s}$.subname at {$.file}:$.line\n"
        }

        method is-hidden  { $!code.?is_hidden_from_backtrace }
        method is-routine { $!code ~~ Routine }
        method is-setting { $!file eq 'src/gen/CORE.setting' }
    }
    proto method new(|$) {*}

    multi method new(Exception $e, Int $offset = 0) {
        self.new(nqp::getattr(nqp::p6decont($e), Exception, '$!ex').backtrace, $offset);
    }

    multi method new() {
        try { die() };
        self.new($!, 3);
    }

    # note that parrot backtraces are RPAs, marshalled to us as Parcel
    multi method new(Parcel $bt, Int $offset = 0) {
        my $new = self.bless(*);
        for $offset .. $bt.elems - 1 {
            next if pir::isnull($bt[$_]<sub>);
            my $code = try {
                pir::perl6_code_object_from_parrot_sub__PP($bt[$_]<sub>);
            };
            my $line     = $bt[$_]<annotations><line>;
            my $file     = $bt[$_]<annotations><file>;
            next unless $line && $file;
            # now *that's* an evil hack
            last if $file eq 'src/stage2/gen/NQPHLL.pm';
            my $subname  = nqp::p6box_s($bt[$_]<sub>);
            $subname = '<anon>' if $subname.substr(0, 6) eq '_block';
            $new.push: Backtrace::Frame.new(
                :$line,
                :$file,
                :$subname,
                :$code,
            );
        }
        $new;
    }

    method next-interesting-index(Int $idx is copy = -1) {
        ++$idx;
        loop (; $idx < $.elems; ++$idx) {
            my $cand = $.at_pos($idx);
            return $idx unless $cand.is-hidden || $cand.is-setting;
        }
        Int;
    }

    method outer-caller-idx(Int $startidx) {
        my %outers;
        my $start   = $.at_pos($startidx).code;
        my $current = $start.outer;
        while $current {
            %outers{$current.static_id} = $start;
            $current = $current.outer;
        }

        ($startidx .. $.end).grep({$.at_pos($_).code && %outers{$.at_pos($_).code.static_id}});
    }

    method nice() {
        my Int $i = self.next-interesting-index // $.end;
        my @frames;
        while $i.defined {
            my $prev = self.at_pos($i);
            my @outer_callers := self.outer-caller-idx($i);
            my ($target_idx) = @outer_callers.keys.grep({self.at_pos($i).code.^isa(Routine)});
            $target_idx    //= @outer_callers[0] // $i;
            my $current = self.at_pos($target_idx);
            @frames.push: $current.clone(line => $prev.line);

            $i = self.next-interesting-index($target_idx);
        }
        @frames.join;
    }

    multi method Str(Backtrace:D:) { self.nice }

    method concise(Backtrace:D:) {
        self.grep({ !.is-hidden && .is-routine && !.is-setting }).join
    }

    method filtered(Backtrace:D:) {
        self.grep({ !.is-hidden && (.is-routine || !.is-setting )}).join
    }

    method full(Backtrace:D:) {
        self.join
    }
}
