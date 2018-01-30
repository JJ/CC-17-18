# -*- cperl -*-

use Test::More;
use Git;
use LWP::Simple;
use File::Slurper qw(read_text);
use Net::Ping;
use Term::ANSIColor qw(:constants);
use JSON;

use v5.14; # For say

my $repo = Git->repository ( Directory => '.' );
my $diff = $repo->command('diff','HEAD^1','HEAD');
my $diff_regex = qr/a\/proyecto\/(\d)\.md/;
my $github;

SKIP: {
  my ($this_hito) = ($diff =~ $diff_regex);
  skip "No hay envío de proyecto", 5 unless defined $this_hito;
  my $diag=<<EOC;

"Failed test" indica que no se cumple la condición indicada
Hay que corregir el envío y volver a hacer el pull request,
aumentando en uno el número de la versión del hito en el
fichero correspondiente.

EOC
  diag $diag;
  my @files = split(/diff --git/,$diff);
  my ($diff_hito) = grep( /$diff_regex/, @files);
  say "Tratando diff\n\t$diff_hito";
  my @lines = split("\n",$diff_hito);
  my @adds = grep(/^\+[^+]/,@lines);
  is( $#adds, 0, "Añade sólo una línea");
  my $url_repo;
  if ( $adds[0] =~ /\(http/ ) {
    ($url_repo) = ($adds[0] =~ /\((http\S+)\)/);
  } else {
    ($url_repo) = ($adds[0] =~ /^\+.+(http\S+)\b/s);
  }
  diag(check( "Encontrado URL del repo $url_repo" ));
  say $url_repo;
  isnt($url_repo,"","El envío incluye un URL");
  like($url_repo,qr/github.com/,"El URL es de GitHub");
  my ($user,$name) = ($url_repo=~ /github.com\/(\S+)\/(.+)/);
  my $repo_dir = "/tmp/$user-$name";
  if (!(-e $repo_dir) or  !(-d $repo_dir) ) {
    mkdir($repo_dir);
    `git clone $url_repo $repo_dir`;
  }
  my $student_repo =  Git->repository ( Directory => $repo_dir );
  my @repo_files = $student_repo->command("ls-files");
  say "Ficheros\n\t→", join( "\n\t→", @repo_files);
  isnt( grep(/proyecto.0.md/, @repo_files), 1, "No es el repositorio de la asignatura");
  for my $f (qw( README.md .gitignore LICENSE )) {
    isnt( grep( /$f/, @repo_files), 0, "$f presente" );
  }

  if ( $this_hito > 0 ) { # Comprobar milestones y eso 
    cmp_ok( how_many_milestones( $user, $name), ">=", 3, "Número de hitos correcto");
    
    my @closed_issues =  closed_issues($user, $name);
    cmp_ok( $#closed_issues , ">=", 0, "Hay ". scalar(@closed_issues). " issues cerrado(s)");
    for my $i (@closed_issues) {
      my ($issue_id) = ($i =~ /issue_(\d+)/);
      
      is(closes_from_commit($user,$name,$issue_id), 1, "El issue $issue_id se ha cerrado desde commit")
    }
  }

  if ( $this_hito > 1 ) { # Comprobar provisionamiento
    isnt( grep( /.yml/, @repo_files), 0, "Hay algún playbook en YAML presente" );
    isnt( grep( /provision/, @repo_files), 0, "Hay un directorio 'provision'" );
    isnt( grep( m{provision/\w+}, @repo_files), 0, "El directorio 'provision' no está vacío" );
  }

  my $README;

  if ( $this_hito > 2 ) { # Comprobar script para acopiar las máquinas 
    isnt( grep( /acopio.sh/, @repo_files), 0, "Está el script de aprovisionamiento" );
    $README =  read_text( "$repo_dir/README.md");
    my ($deployment_ip) = ($README =~ /(?:[Dd]espliegue|[Dd]eployment):.*?(\S+)\s+/);
    SKIP: {
      skip "Ya en el hito siguiente", 1 unless $this_hito < 4;
      check_ip($deployment_ip);
    };
  }

  if ( $this_hito > 3 ) { # Comprobar script para acopiar las máquinas
    isnt( grep( /orquestacion/, @repo_files), 0, "Hay un directorio 'orquestacion'" );
    
    isnt( grep( m{orquestacion/Vagrantfile}, @repo_files), 0, "El directorio 'orquestacion' tiene un fichero 'Vagrantfile'" );
    my $vagrantfile = read_text( "$repo_dir/orquestacion/Vagrantfile");
    like($vagrantfile,qr/vm.provision/,"El Vagrantfile incluye provisionamiento");

    my ($deployment_ip) = ($README =~ /Despliegue Vagrant:\s*(\S+)\s+/);
  SKIP: {
      skip "Ya en el hito siguiente", 1 unless $this_hito < 5;
      check_ip($deployment_ip);
    }
  }

  if ( $this_hito > 4 ) { # Despliegue en algún lado
    my ($deployment_url) = ($README =~ /(?:[Cc]ontenedor|[Cc]ontainer).+(https?:..\S+)\b/);
    if ( $deployment_url ) {
      diag "☑ Detectado URL de despliegue $deployment_url";
    } else {
      diag "✗ Problemas detectando URL de despliegue";
    }
    isnt( $deployment_url, "", "URL de despliegue hito 5");
    my $status = get "$deployment_url/status";
    isnt( $status, undef, "Despliegue hecho en $deployment_url" );
    my $status_ref = from_json( $status );
    like ( $status_ref->{'status'}, qr/[Oo][Kk]/, "Status de $deployment_url correcto");
    
    isnt( grep( /Dockerfile/, @repo_files), 0, "Dockerfile presente" );

    my ($dockerhub_url) = ($README =~ m{(https://hub.docker.com/r/\S+)\b});
    diag "Detectado URL de Docker Hub '$dockerhub_url'";
    my $dockerhub = get $dockerhub_url;
    like( $dockerhub, qr/Last pushed:.+ago/, "Dockerfile actualizado y en Docker Hub");
  }

   if ( $this_hito > 5 ) { # Despliegue combinado
    my ($deployment_url) = ($README =~ /(?:[Hh]ito6).+(https?:..\S+)\b/);
    if ( $deployment_url ) {
      diag "☑ Detectado URL de despliegue $deployment_url";
    } else {
      diag "✗ Problemas detectando URL de despliegue";
    }
    isnt( $deployment_url, "", "URL de despliegue hito 6");
    my $status = get "$deployment_url/status";
    isnt( $status, undef, "Despliegue correctamente realizado en $deployment_url" );
    my $status_ref = from_json( $status );
    like ( $status_ref->{'status'}, qr/[Oo][Kk]/, "Status de $deployment_url correcto");
    
    isnt( grep( /docker-compose.yml/, @repo_files), 0, "Fichero de docker-compose presente" );

  }

};

done_testing();


# ------------------------------- Subs -----------------------------------

sub how_many_milestones {
  my ($user,$repo) = @_;
  my $page = get( "https://github.com/$user/$repo/milestones" );
  my ($milestones ) = ( $page =~ /(\d+)\s+Open/);
  return $milestones;
}

sub closed_issues {
  my ($user,$repo) = @_;
  my $page = get( "https://github.com/$user/$repo".'/issues?q=is%3Aissue+is%3Aclosed' );
  my (@closed_issues ) = ( $page =~ m{<li\s+(id=.+?</li>)}gs );
  return @closed_issues;

}

sub closes_from_commit {
  my ($user,$repo,$issue) = @_;
  my $page = get( "https://github.com/$user/$repo/issues/$issue" );
  return $page =~ /closed\s+this\s+in/gs ;

}

sub check {
  return BOLD.GREEN ."✔ ".RESET.join(" ",@_);
}

sub fail_x {
  return BOLD.MAGENTA."✘".RESET.join(" ",@_);
}

sub check_ip {
  my $ip = shift;
  if ( $ip ) {
    diag "\n\t".check( "Detectada dirección de despliegue $ip" )."\n";
  } else {
    diag "\n\t".fail_x( "Problemas detectando URL de despliegue" )."\n";
  }
  my $pinger = Net::Ping->new();
  $pinger->port_number(22); # Puerto ssh
  isnt($pinger->ping($ip), 0, "$ip es alcanzable");
}
