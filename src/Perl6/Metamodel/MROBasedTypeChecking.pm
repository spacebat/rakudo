role Perl6::Metamodel::MROBasedTypeChecking {
    method isa($obj, $type) {
        my $decont := pir::nqp_decontainerize__PP($type);
        for self.mro($obj) {
            if pir::nqp_decontainerize__PP($_) =:= $decont { return 1 }
        }
        0
    }
    
    method type_check($obj, $checkee) {
        # The only time we end up in here is if the type check cache was
        # not yet published, which means the class isn't yet fully composed.
        # Just hunt through MRO.
        for self.mro($obj) {
            if $_ =:= $checkee {
                return 1;
            }
            if pir::can($_.HOW, 'does_list') {
                my @does_list := $_.HOW.does_list($_);
                for @does_list {
                    if $_ =:= $checkee {
                        return 1;
                    }
                }
            }
        }
        0
    }
    
    method publish_type_cache($obj) {
        my @tc;
        for self.mro($obj) {
            @tc.push($_);
            if pir::can($_.HOW, 'does_list') {
                my @does_list := $_.HOW.does_list($_);
                for @does_list {
                    @tc.push($_);
                }
            }
        }
        pir::publish_type_check_cache($obj, @tc)
    }
}