#!/usr/bin/perl
#Script to do backup on nexpose tool. This script do the backup and send it compacted to a remote host using SCP.
#Script para realizar backup da ferramenta nexpose. Além de fazer o backup, o script envia o arquivo de backup compactado para um host remoto via SCP.
#Autor: Alan Santos - alanwds@gmail.com
#Use for free :)

#Declaracao de classes

use warnings;
use strict;

#Declaracao de classe para controle de date/time (dependencas perl-DateTime.x86_64)
use DateTime; 

#Declaracao de modulo para utilizacao de ssh e manipulacao de arquivos
#Dependencias: modulo scp expect 
#perl -MCPAN -e 'install Net::SCP::Expect' 
use Net::SCP::Expect;

#Declaracao de modulo para realizar conexoes ssh
#Dependencias: modulo ssh perl
#perl -MCPAN -e 'install Net::SSH::Perl' ou 'yum install perl-Net-SSH.noarch'
use Net::SSH::Perl;

#Classe para tratamento de parametros
use Getopt::Std;

#Declaracao de variaveis
our $confirm = '';

#Variaveis para uso do syslog
our $facility = 'daemon';
our $logLevel = 'info';
our $syslogServer = '127.0.0.1';
our $userBackup="userbkp";
our $passBackup="yourpassword";
our $urlVsLogin="https://nexpose_url:3780/login.html";
our $parametrosLogin="\'loginRedir=home.html\&nexposeccusername=$userBackup\&nexposeccpassword=$passBackup\'";
our $cookieSessao="./cjar";
our $comandoShell="";
our $parametrosHeader="";
our $parametrosDoBackup="\'targetTask=backupRestore&cmd=backup&backup_desc=auto_bkp&platform_independent=true\'";
our $urlVsMaintCMD="https://vs1.mss.intranet:3780/admin/global/maintenance/maintCmd.txml";
our $parametrosMaintMode="\'targetTask=maintModeHandler&cmd=getTaskStatus&includeHistory=true&returnFullHistory=false\'";
our $parametrosRebootConsole="\'targetTask=maintModeHandler&cmd=restartServer&cancelAllTasks=false\'";
our $logVs="/opt/Symantec/CCSVM/nsc/logs/nsc.log";
our $pathBackups="/opt/Symantec/CCSVM/nsc/backups/";
our $maquinaBackup="ip_with_ssh_server_to_store_backup";
our $userMaquinaBackup="user_ssh";
our $passMaquinaBackup="pass_ssh";
our $pathMaquinaBackup="/path/to/store/backup/";

#declara o array para pegar os parametros
my %args = ();

#Associa os parametros ao array criado acima (%args) 
getopts(":hy", \%args);

#Trata os parametros

#Exibe help
if($args{h}){
	
	&exibeHelp();
}

if(!$args{y}){

	&exibeWarning();
}

#Inicio das funcoes

#Funcao para log das mensagens do script
sub LOG{

        #Armazena a data e hora em uma variavel
        my $now = `date +"%b %d %R:%S"`;

        #remove a quebra de linha da data/hora
        chomp($now);

        #Recebe a string como parametro
        my ($logitem) = @_;

        #Adiciona a data/hora, espaco e a quebra de linha na linha
        $logitem = $now . " " . $logitem."\n";

        #Abre o arquivo de LOG
        open LOG, ">>backupMaster.log" or die $!;

        #Armazena a strings recebida no arquivo
        print LOG $logitem;

        #Fecha o arquivo
        close LOG;

	#Armazena a informacao no syslog
	my $temp = `/usr/bin/logger -i -p daemon.info $logitem`;
	
	#Joga a string no stdout
        print $logitem;

}

#Funcao para exibir o help
sub exibeHelp(){

        print "Modo de usar: backupMaster.pl [parametro]\n";
        print "\nh - Exibe esse help ";
        print "\ny - Modo nao interativo\n";

}

#Verificar se o parametro -y foi passado. Caso nao, essa funciona sera acionada para exibir o hardening e confirmar (ou nao) a execucao do backup
sub exibeWarning { 

	print "ATENCAO: REALIZAR ESSE BACKUP IRA DEIXAR A CONSOLE INDISPONIVEL E IRA CANCELAR TODOS OS JOBS EM ANDAMENTO.";
	print "\nDESEJA CONTINUAR? [y/n]";

	chomp ($confirm = <>);

	if ( $confirm eq 'y'){
		LOG "Iniciando execucao do script.";
	}else{
		LOG "Execucao cancelada. Encerrando script";
		exit 0;
	}
	
}

#Funcao para realizar login na aplicacao 
sub executaLogin{

	#Monta o comando a ser executado no shell 
	$comandoShell = 'curl -k --cookie-jar ' . $cookieSessao . ' --data ' . $parametrosLogin . ' ' . $urlVsLogin; 

	LOG "Efetuando login na aplicao";	

	#Executa o comando e armazena a saida em uma variavel
	my $resultado = `$comandoShell 2>&1`;

	#Verifica se o login foi efetuado com sucesso
	if ($resultado =~ "errorMessage"){
		LOG "ERRO_BKP_VS: Falha no login. Usuario ou senha invalidos?";
		LOG "Cancelando execucao";
		exit 0;
	}else{
		LOG "Login efetuado com sucesso";
	}

}

#Funcao para tratar o cookie e pegar o header necessario para persistir a sessao
sub trataCookie{

	LOG "Filtrando o cookie para armazenar o header";

	#Pega o header necessario
	my $resultado = `grep nexposeCCSessionID $cookieSessao 2>&1`;

	#Verifica se o SessionID foi extraido com sucesso 
        if ($resultado =~ "nexposeCCSessionID"){
                LOG "SessionID extraido com sucesso";
        }else{
		LOG "ERRO_BKP_VS: Falha na extracao do SessionID";
                LOG "Cancelando execucao";
                exit 0;

        }

	
	#Faz o split da string para coletar a informacao de interesse
	my @arrayResultado = split(' ', $resultado);	

	LOG "Concatenando cookie para gerar o header";
	#Monta o parametro do header
	$parametrosHeader = "\'" . $arrayResultado[5] . ": " . $arrayResultado[6] . "\'";

	return $parametrosHeader;

}

#Funcao para colocar o backup na fila de tarefas da aplicacao
sub doBackup{

	LOG "Colocando o job backup na fila de tarefas do CCSVM"; 
	$comandoShell = 'curl -v -k --header ' . $parametrosHeader . ' --cookie ' . $cookieSessao . ' --data ' . $parametrosDoBackup . ' ' . $urlVsMaintCMD; 

	my $resultado = `$comandoShell  2>&1`;
	
	#Verifica se a task foi inserida corretamente
	if ($resultado =~ "HTTP/1.1 200 OK"){
		LOG "Task inserida com sucesso";
	}else{
		LOG "ERRO_BKP_VS: Nao foi possivel inserir a task";
	}

}

#Funcao para entrar no modo de manutencao
sub maintMode{

	LOG "Entrando no modo de manutencao";

	$comandoShell = 'curl -v -k --header ' . $parametrosHeader . ' --cookie ' . $cookieSessao . ' --data ' . $parametrosMaintMode . ' ' . $urlVsMaintCMD;

	my $resultado = `$comandoShell  2>&1`;

        #Verifica se a task foi inserida corretamente
        if ($resultado =~ "result  succeded=\"true\""){
                LOG "Modo manutencao ativado com sucesso";
        }else{
                LOG "ERRO_BKP_VS: Nao foi possivel entrar no modo de manutencao";
        }

}

#Funcao para reiniciar a console
sub rebootConsole{

	LOG "Reiniciando a console";
	$comandoShell = 'curl -v -k --header ' . $parametrosHeader . ' --cookie ' . $cookieSessao . ' --data ' . $parametrosRebootConsole . ' ' . $urlVsMaintCMD;

	my $resultado = `$comandoShell  2>&1`;

        #Verifica se a task foi inserida corretamente
        if ($resultado =~ "result  succeded=\"true\""){
                LOG "Reboot realizado com sucesso";
        }else{
                LOG "ERRO_BKP_VS: Nao foi possivel rebootar a console";
        }

}

#Funcao para verificar se a console esta no modo de manutencao
sub isMaintMode{

	LOG "Verificando se a console esta no modo de manutencao";
	$comandoShell = 'curl -v -k ' . $urlVsLogin;
	
	my $resultado = `$comandoShell  2>&1`;

	#Verifica se a console esta no modo de manutencao
        if ($resultado =~ "maintenance"){
                LOG "Console no modo de manutencao";
		return 1;
        }else{
                LOG "Console no modo normal ou em inicializacao";
		return 0;
        }

}

#Funcao para verificar se a console esta em processo de inicializacao
sub isBootMode{

        LOG "Verificando se a console esta em processo de inicializacao";
        $comandoShell = 'curl -v -k ' . $urlVsLogin;

        my $resultado = `$comandoShell  2>&1`;

	#Verifica se a console ainda esta parada (por causa do restar manual)
	if($resultado =~ "Connection refused"){
                LOG "Console iniciando processo de boot";
                return 1;
	}

        #Verifica se a console esta em processo de inicializacao 
        if ($resultado =~ "initializing"){
                LOG "Console em processo inicializacao";
                return 1;
        }else{
                LOG "Console no modo normal ou em inicializacao";
                return 0;
        }

}


sub isBackupComplete{

	LOG "Verificando se o backup foi concluido";

	#Coleta as 10 ultimas linhas do arquivo de logs da console
	$comandoShell = 'tail -10 ' . $logVs; 

	my $resultado = `$comandoShell  2>&1`;

	#Verifica se o backup realmente terminou
	if (($resultado =~ "Database roles backup completed") && ($resultado =~ "Security Console web interface ready")){
	
		LOG "Backup concluido com sucesso";
		return 1;

	} else {
		LOG "Backup ainda nao concluido";
		return 0;
	}

	
}

sub rebootConsoleShell(){
	
	LOG "Reiniciando aplicacao via shell";

	$comandoShell = `service ccsvmd restart`;
	my $resultado = `$comandoShell  2>&1`;

	#Verifica se a console foi reiniciada com sucesso
        if (($resultado =~ "FAILED")){

                LOG "ERRO_BKP_VS: Falha ao reiniciar console. Favor verificar";
                return 1;

        } else {
                LOG "Console reiniciada com sucesso";
                return 0;
        }


}	 

sub solucaoDeContornoBackup(){
#Solucao de contorno com relacao ao problema de backup
#Aqui sera verificado se a console esta em modo de manutencao e se o backup ja foi concluido, caso os dois sejam verdadeiros, havera o restart manual da console do VS

	my $maintMode = isMaintMode();
	my $backupComplete = isBackupComplete();
        if (($maintMode == '1') && ($backupComplete = '1')){
                LOG "Backup concluido, mas console ainda em modo de manutencao. Necessario reboot manual";
		rebootConsoleShell();
        }else{
                LOG "Console OK";
        }
}

sub doTests{
#Testa se a console ainda esta em modo de manutencao. Se estiver, aplicara a solucao de contorno, se nao, continua o script, ele fara isso enquanto a console estiver no modo de manutencao
#Antes de testar, ele aguarda 20 segundos para garantir que o backup foi iniciado e a console entrou em modo de manutencao

        sleep(20);
        while ((isMaintMode()) || (isBootMode())){

                LOG "Console permanece no modo de manutencao ou em modo de inicializacao";
                LOG "Verificando a necessidade de aplicar solucao de contorno";
                solucaoDeContornoBackup();

                #Aguarda 15 segundos antes de tentar novamente
                sleep(15);
        }
}

#Funcao para montar o nome default do backup, baseando-se na data atual e no formato nxbackup_AAAA_MM_DD.zip
sub getNomeBackup{

	#Calcula a data para concatenar com o nome do backup (nxbackup)
	my $date = DateTime->now;

	my $nomeDefaultBackup = 'nxbackup_' . $date->ymd('_') . '.zip';

	return $nomeDefaultBackup;

}

#Funcao para enviar o backup para a maquina de backup (definida na variavel $maquinaBackup). 
sub sendBackup{

	my ($nomeDefaultBackup) = @_;
	
	LOG "Enviando o backup para a maquina backup $maquinaBackup";

	#Inicia o objeto scp	
	my $scp = Net::SCP::Expect->new(host=>$maquinaBackup,user=>$userMaquinaBackup,password=>$passMaquinaBackup,recursive=>1);

	my $file = $pathBackups . $nomeDefaultBackup;

	#Envia o arquivo para a maquina de backup
	$scp ->scp($file,$pathMaquinaBackup) or LOG "ERRO_BKP_VS: Nao foi possivel copiar arquivo para a maquina remota"; 

}

#Funcao para apagar os backups antigos (Maior que duas semanas)
sub backupRotate{

	LOG "Iniciando o rotate dos backups";

	#Instancia o objeto ssh
	my $ssh = Net::SSH::Perl->new($maquinaBackup);

	LOG "Fazendo login na maquina $maquinaBackup";
	#Faz a autenticacao
	$ssh->login($userMaquinaBackup, $passMaquinaBackup);

	LOG "Verificando se existem arquivos a serem deletados";

	$comandoShell = 'find /opt/backup/vs/ -name "nxbackup*" -atime +14 -delete -print';

	#Executa o comando
	my($stdout, $stderr, $exit) = $ssh->cmd($comandoShell);

	#Testa para verificar se houve erro na execucao do comando
        if($stderr){
                LOG "ERRO_BKP_VS: Nao foi possivel executar o comando";
                LOG "ERRO_BKP_VS: $stderr";
        }else{
                LOG "Comando executado com sucesso";
        }

	#Testa se existe stdout. Se existe e pq os arquivos foram deletados

	if($stdout){

		LOG "Os seguintes arquivos foram encontrados e apagados";
		LOG "$stdout";

	}else{
		LOG "Nao foram encontrados backups antigos";
	}

}

#Inicia as chamadas de funcao
executaLogin();
trataCookie();
doBackup();
maintMode();
rebootConsole();
doTests();
sendBackup(getNomeBackup());
backupRotate();

LOG "Fim do script";
