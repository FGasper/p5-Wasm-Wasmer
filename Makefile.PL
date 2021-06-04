
#my $wasmer_cflags = `~/.wasmer/bin/wasmer config --cflags`;
#my $wasmer_cflags = '-I/Users/felipe/.wasmer/include';

#my $wasmer_lflags = `~/.wasmer/bin/wasmer config --libs`;
#print "LFLAGS: $wasmer_lflags\n";

my $wasmer_cflags = `wasmer config --cflags`;
die 'no cflags' if !$wasmer_cflags;
my $wasmer_lflags = `wasmer config --libs`;
die 'no lflags' if !$wasmer_lflags;

use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'Wasm::Wasmer',
    VERSION_FROM      => 'lib/Wasm/Wasmer.pm', # finds $VERSION
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/Wasm/Wasmer.pm', # retrieve abstract from module
       AUTHOR         => [
            'Felipe Gasper (FELIPE)',
        ],
      ) : ()
    ),
    LIBS              => [$wasmer_lflags], # e.g., '-lm'
    DEFINE            => '', # e.g., '-DHAVE_SOMETHING'
    INC               => "-Wall -I. --std=c99 $wasmer_cflags",
    LICENSE           => "perl_5",

    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url => 'git://github.com/FGasper/p5-Wasm-Wasmer.git',
                web => 'https://github.com/FGasper/p5-Wasm-Wasmer',
            },
            bugtracker => {
                web => 'https://github.com/FGasper/p5-Wasm-Wasmer/issues',
            },
        },
    },

    TEST_REQUIRES => {
        'Test::More' => 0,
        'Test::Deep' => 0,
        'Test::FailWarnings' => 0,
        'File::Temp' => 0,
    },
);
