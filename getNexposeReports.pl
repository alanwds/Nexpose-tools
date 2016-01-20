#!/usr/bin/perl -w
#Script to get reports from Nexpose API. The script get the reports and put all information about it on a CSV file (that can be parsed later).
#Script para conectar na API do Nexpose e coletar os relatorios de clientes. O script faz o download dos relatórios e insere as informações em um arquivo CSV(que pode ser parseado posteriormente).

#Autor: Alan Santos - pro_awsantos@uoldiveo.com
#Data: 19/04/2013

#Declaracao de modulos
use warnings;
use strict;
use Rapid7::NeXpose::API; #Modulo para gerenciar a API
use utf8;
use POSIX qw(strftime); #Modulo para para data
use Class::CSV; #Modulo para trbalhar com arquivos CSV
use Getopt::Std; #Modulo para trabalhar com parametros
use DBI; #Modulo para trabalhar com querys nos arquivos CSV
use Date::Calc qw(Week_of_Year); #Modulo para trabalhar com semanas

#Declaracao de variaveis globais
our $pathVS = 'https://ip_nexpose:3780';
our $userVs = 'apiUser';
our $passVs = '123@mudar';
our $urlApi = '/api/1.1/xml'; #Para os relatorios, sera utilizado a API;
our $urlVS = $pathVS . $urlApi;
our $sessionAPI = '';
our $parametroPeriodicidade = '';
my @idConfToCsvFile = '';
our $pathRelatorio = '/opt/relatorios_vs/vs1';
our $pathBackupRelatorio = '/opt/relatorios/vs/';
my @filesToCsv;
my $outfile = '';

#Inicia o diretorio corrente como "banco de dados" com o encode utf8
our $dbh = DBI->connect ("dbi:CSV:", undef, undef, { f_dir => "/", f_encoding => "utf8" });

#TRATA A PASSAGEM DE PARAMETROS
#Estancia um array para receber os parametros
my %parametros = ();

#Associa os parametros as posicoes do array
getopts(".:p:f:.", \%parametros);

if((!$parametros{p}) || (!$parametros{f})){

        &exibeHelp();

}else{
        #Atribui os parametros as variaveis que serao utilizadas no script
        $parametroPeriodicidade = $parametros{p};
        $outfile = $parametros{f};
}
#/TRATA A PASSAGEM DE PARAMETROS

#Inicio das funcoes

#FUNCAO QUE EXIBE O HELP
sub exibeHelp{

        print "\nModo de usar: $0 -p [m|s] -f [nome_arquivo.csv]\n\n";

        print "p: Periodicidade do relatorio. Utilize 's' para semanal ou 'm' para mensal\n";
        print "f: Arquivo CSV no qual a saida do script sera salva\n\n";
        exit 0;
}

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
        open LOG, ">>/var/log/runReportVS.log" or die $!;

        #Armazena a strings recebida no arquivo
        print LOG $logitem;

        #Fecha o arquivo
        close LOG;

        #Armazena a informacao no syslog
        my $temp = `/usr/bin/logger -i -p local7.info -t \"Painel_VS\" $logitem`;

        #Joga a string no stdout
        print $logitem;

}

#Funcao que retorna a data corrente
sub getCurrentDate{

        my $date = strftime "%d-%m-%Y", localtime;

        return $date;

}

#Funcao para verificar periodicidade dos relatorio
sub checkPeriodicidade{

my $periodicidade = $_[0];
my $keyWords = '';

#Somente relatorios que tiverem as palavras abaixo serao enviados ao painel. Caso haja necessidade de enviar um novo modelo, o nome deve ser padronizado com uma palavra chave, a e mesma deve ser inserida nessa variavel
#As keyWord serao definidas pela periodicidade do relatorio, tal periodicidade e definida pela variavel $periodicidade, que sera recebida como parametro na execucao do script

        if($periodicidade eq 's'){

                LOG "Iniciando script para relatorios semanais";
                $keyWords = '[S|s]emanal';

        }elsif($periodicidade eq 'm'){

                LOG "Iniciando script para relatorios Mensais";
                $keyWords = '[M|m]ensal';
        }else{
                LOG "ERRO: Periodicidade nao definida";
                LOG "ERRO: Finalizando script";
                exit 0;
        }

        return $keyWords;
}


#Efetua o login pela API

sub loginAPI{

LOG "Efetuando login na API";

$sessionAPI = Rapid7::NeXpose::API->new(
                    url=>$pathVS,
                    user=>$userVs, password=>$passVs, nologin=>1
            );
}

#FUNCAO PARA PEGAR AS CONFIGURACOES DO REPORT
sub getReportConfig{

#Array que vai conter todos os IDs desejados
my @configIdrelatorios = @_;
my $count = '0';
my $temp = '';
my $keyWords = checkPeriodicidade($parametroPeriodicidade);
my @idConfToCsvFile;

        LOG "Coletando as configuracoes dos reports";

        #Percorre o vetor a fim de coletar as informacoes do scan e trata-los conforme a necessidade
        foreach (@configIdrelatorios){

                #Verifica se existe valor na variavel $_ (que representa o id da configucao do report), caso sim, ele ira coletar os dados necessarios, caso contratio, sera ignorado
                if ($_){
                        my $reportConfigList = $sessionAPI->reportconfiglist($_);
                        $temp = $reportConfigList->[0]->{'name'};

                        #Verifica se o relatorio contem as palavras chaves (Definida na variavel $keyWords na funcao checkPeriodicidade())
                        if($temp =~ /$keyWords/){
                                #Caso de match, havera um segundo teste para saber se o CNPJ esta presente, se nao tiver, sera enviado um erro para o LOG
                                if($temp =~ /[0-9]{2,3}\.[0-9]{3}\.[0-9]{3}\/[0-9]{4}-[0-9]{2}/){

                                        LOG "CNPJ presente no relatorio $temp";
                                        LOG "Armazenando relatorio $temp para serem enviados ao arquivo CSV";
                                        #Se a variavel $_ nao for fazia, ele adiciona no vetor @idConfToCsvFile
                                        push(@idConfToCsvFile, $_) unless (!$_);
                                }else{

                                        LOG "ERRO: CNPJ nao esta presente no relatorio $temp. Favor verificar";
                                }

                        }else{ #Caso nenhum dos criterios seja atendido, havera um LOG indicando que aquele relatorio foi ignorado

                                LOG "ERRO: Relatorio $temp nao esta dentro do padrao esperado, portanto sera ignorado";

                        }

                }

                #Incrementa o contador
                $count++;

        }

        #Retorna o vetor somente com os id de configuracao validos, que serao enviados para o arquivo CSV
        return @idConfToCsvFile;

}

#FUNCAO PARA PEGAR TODAS AS INFORMACOES DO RELATORIO E ARMAZENAR EM UM ARRAY PARA SER ENVIADO AO ARQUIVO CSV
sub getReportInformation{

my $count = '0';
my $idConfToCsvFile = $_[0];
my $cfgId = '';
my $urlReport = '';
my @infoReportToCsv;

        #Gera o objeto com as informacoes do report
        my $reportList = $sessionAPI->reportlist();

        LOG "Coletando ID do relatorio";

        #percorre o vetor ate encontrar o cfg-id desejado e armazena no vetor @infoReportToCsv
        do{

                #Atribui o ID encontrado a variavel cfgID para efetuar as comparacoes necessarias
                $cfgId = $reportList->[$count]->{'cfg-id'};

                #Testa para ver se o id e igual, se for ele ira armazenar o vetor
                if($idConfToCsvFile eq $reportList->[$count]->{'cfg-id'}){

                        #Armazena a URL numa variavel
                        $urlReport = $reportList->[$count]->{'report-URI'};

                        LOG "Id encontrado. Inserindo informacao no vetor";

                        push(@infoReportToCsv,$idConfToCsvFile);
                        push(@infoReportToCsv,$urlReport);

                }

                #Incrementa o contador
                $count++;

        } while($idConfToCsvFile ne $cfgId);

        #Retorna o array @infoReportToCsv;
        return @infoReportToCsv;

}

#FUNCAO PARA PEGAR O ID DE TODOS OS RELATORIOS SEMANAIS E MENSAIS

#Essa funcao ira armazenar os IDs em um vetor. ATENCAO, aqui havera o filtro dos relatorios mensais e semanais. Caso haja alguma alteracao de regra de negocio, e importante se atentar a essa funcao

sub getIdReports{

my $count = '0';
my $templateId = '';
my $cfgId = '';
my @idConfReport = '';

        LOG "Coletando lista de relatorios disponiveis";
        my $reportList = $sessionAPI->reportlist();

        do {

                #Atribui o id do report a variavel $templateId
                $templateId = $reportList->[$count]->{'template-id'};

                $cfgId = $reportList->[$count]->{'cfg-id'};

                #Testa se o templateID existe, se existir ira armazenar o id de configuracao no vetor idConfReport
                if($templateId){

                        #LOG "Armazenando o ID de configuracao de report $cfgId na lista de reports";
                        push(@idConfReport,$cfgId);
                }

                #Incrementa o contador
                $count++;

        } while ($templateId);

        #Retorna o array com todos os id de configuracao de reports que serao utilizados
        return @idConfReport;

}

#FUNCAO PARA PEGAR O NOME DO RELATORIO

sub getReportName{

my $cfgId = $_[0];
my $reportedOn = $_[1];
my $reportName = '';

#Armazena a data para ser inserida no nome do arquivo

        LOG "Coletando nome do relatorio";

        my $reportConfigList = $sessionAPI->reportconfiglist($cfgId);
        $reportName = $reportConfigList->[0]->{'name'};

        #Remove o CNPJ e deixa apenas o nome do relatorio + periodicidade
        $reportName =~ s/[0-9]{2,3}\.[0-9]{3}\.[0-9]{3}\/[0-9]{4}-[0-9]{2}//g;

        #Remove o "- " do final da string
        $reportName =~ s/-\ $//g;

        #Substitui as barras da data por underline para facilitar a nomenclatura
        $reportedOn =~ s/\//_/g;

        $reportName = $reportName . "- " . $reportedOn;

        return $reportName;

}

#FUNCAO PARA PEGAR O CNPJ DO CLIENTE

sub getCnpj{

my $cfgId = $_[0];
my $cnpj = '';

        LOG "Coletando CNPJ do cliente/relatorio";

        my $reportConfigList = $sessionAPI->reportconfiglist($cfgId);
        $cnpj = $reportConfigList->[0]->{'name'};

        #Expressao regular para pegar o cnpj
        $cnpj =~ /([0-9]{2,3}\.[0-9]{3}\.[0-9]{3}\/[0-9]{4}-[0-9]{2})/;
        $cnpj = $1;

        #Trata cnpj para remover ".","/" e "-"
        $cnpj =~ s/\.//g;
        $cnpj =~ s/\-//g;
        $cnpj =~ s/\///g;

        return $cnpj;

}

#FUNCAO PARA CONVERTER A DATA DO FORMATO ISO 8601 PARA O FORMATO DD/MM/AAAA

sub isoDate2normalDate{

my $isoDate = $_[0];
my @retornos;
my $normalDate = '';

        (@retornos) = split(//,$isoDate);

        $normalDate = $retornos[6] . $retornos[7] . "/" . $retornos[4] . $retornos[5] . "/" . $retornos[0] . $retornos[1] . $retornos[2] . $retornos[3];

        return $normalDate;

}

#FUNCAO PARA PEGAR A DATA DE GERACAO DO RELATORIO

sub getGeneratedOn{

my $cfgId = $_[0];
my $cfgIdApi = '';
my $generatedOn = '';
my $count = '0';

        LOG "Coletando data de geracao do relatorio";

        my $reportList = $sessionAPI->reportlist();

        #Vai percorrer todo o objeto ate que o id de configuracao retornado pela api seja igual ao id da api que foi passado como parametro
        do {

                #Atribui o id do report a variavel $templateId
                $generatedOn = $reportList->[$count]->{'generated-on'};

                #Atribui o id de configuracao a variavel cfgIdApi
                $cfgIdApi = $reportList->[$count]->{'cfg-id'};

                #Incrementa o contador
                $count++;

        } while ($cfgId ne $cfgIdApi);

        return $generatedOn;


}

#FUNCAO PARA PEGAR O NOME REAL DO ARQUIVO DO RELATORIO

sub getRealReportName{

my $reportName = $_[0];
my $realReportName = '';

        #Aplica a expressao regular para trocar todos os espacos por underline
        $reportName =~ s/\ /_/g;

        #Adiciona a extensao .pdf no final do nome do arquivo
        $reportName = $reportName . ".pdf";
        $realReportName = $reportName;

        return $realReportName;

}

#FUNCAO PARA MONTAR O CSV CONFORME COM AS INFORMACOES DO RELATORIO

sub doParseCsv{

#Recebe as informacoes via parametro e passa a variavel infoReportToCsv
my @infoReportToCsv = @_;
my $idReport = $infoReportToCsv[0];
my $urlReport = $pathRelatorio . $infoReportToCsv[1];

#Vetor para armazenar todas as linhas que serao insidas no CSV
my @filesToCsv;

#Flag para indicar que o relatorio ainda nao foi enviado
my $sent = 0;
#Armazena a descricao do arquivo.
my $description = '[MSS UOLDIVEO] Relatório de Segurança';

#Pega a data de geracao do relatorio
my $generatedOn = isoDate2normalDate(getGeneratedOn($idReport));
#Pega o nome do relatorio (que sera exibido no painel dos clientes)
my $reportName = getReportName($idReport,$generatedOn);
#Pega o real name do relatorio (como sera armazenado no file system do painel)
my $realReportName = getRealReportName($reportName);
#Pega o CNPJ do cliente
my $cnpj = getCnpj($idReport);
#Campo para enviar ou nao o email. Por default sera true, ou seja, envia o email
my $sendMail = 'true';
#Campo para o assunto do email. Por default "[MSS UOLDIVEO] Relatório de Segurança"
my $subjectMail = $description;
#Campo para o corpo do email.
my $bodyMail = 'Um novo Relatório de Segurança (MSS) referente ao período 6/2013 está disponível. Acesse o Painel do Cliente <b>UOLDIVEO</b> para efetuar o download.<br><br>Em caso de dúvidas, contatar o Service Desk pelo telefone <b>11 4003 1100, Painel do Cliente ou e-mail</b> aberturadechamado@uoldiveo.com.<br><br> Atenciosamente,<br><br><b>Equipe de Segurança da Informação <br>MSS UOLDIVEO</b>';
my $separador = '%';
my $linhaCsv = '';

        #Monta a linha que sera enviada para o arquivo CSV
        #A linha deve ter os seguintes campos: Flag de envio, email do contato, cnpj, path arquivo, nome do arquivo, nome de exibicao do arquivo, descricao, data de geracao do arquivo
        $linhaCsv = $sent . $separador . $cnpj . $separador . $sendMail . $separador . $subjectMail . $separador . $bodyMail . $separador . $urlReport . $separador . $reportName . $separador . $realReportName . $separador . $description . $separador . $generatedOn;

        #Para debug
        #print "A linha csv e: \n$linhaCsv";

        #Insere a linha no vetor @filesToCsv
        push(@filesToCsv, $linhaCsv);

        return @filesToCsv;

}

#FUNCAO PARA VERIFICAR SE DETERMINADA ENTRADA JA FOI INSERIDA NO ARQUIVO CSV
sub checkSended{

my $cnpj = $_[0];
my $week = $_[1];
my $month = $_[2];
my $outfile = $_[3];
my $query = '';
my $retorno = '';

        #Testa a periodicidade. Dependendo da periodicidade, a query sera consultada por mes ou por semana
        if ($parametroPeriodicidade eq 's'){

                $query = "SELECT * FROM $outfile where cnpj = $cnpj and week = $week";

        }elsif($parametroPeriodicidade eq 'm'){

                $query = "SELECT * FROM $outfile where cnpj = $cnpj and month = $month";

        }else{

                LOG "ERRO: Periodicidade desconhecida. Encerrando script";
                exit 0;
        }

        #Executa a query
        my $sth = $dbh->prepare ($query);
        $sth->execute ();

        #Percorre os resultados, caso haja algum, retorna 0, indicando que essa entrada ja existe no arquivo csv
        while (my $row = $sth->fetchrow_hashref) {
                $retorno = $row->{cnpj};
        }

        #Testa para verificar se houve algum retorno da query executada, caso sim sera retorna 1 e nao havera a insercao dessa entrada
                if($retorno){
                        LOG "Arquivo ja se encontra no arquivo csv para envio ao painel";
                        $retorno = '1';
                }else{
                        LOG "Arquivo ainda nao enviado ao arquivo CSV";
                        $retorno = '0';
                }


        #Termina a consulta
        $sth->finish ();

        #Retorna o resultado da consulta
        return $retorno;

}

#FUNCAO QUE RECEBE O ARRAY COM AS LINHAS DOS ARQUIVOS A SEREM ENVIADOS PARA O PAINEL E MONTA O ARQUIVO.CSV

sub writeCsvFile{

my @filesToCsv = @_;

#Pega a data corrente
my $date = getCurrentDate();

my $separador = '%';

#Pega o dia, mes e ano corrente
my($day,$month,$year) = split("-",$date);

#Pega o ID da semana atual
my $week = Week_of_Year($year,$month,$day);

#Variavel para armazenar as querys
my $query = '';


#Testa se o arquivo existe, caso exista ele sera criado
#A variavel $outfile e definida no inicio do script, atraves do parametro -f
unless (-e $outfile) {
        LOG "O arquivo $outfile nao existe.";
        LOG "Criando arquivo.";
        $query = "CREATE TABLE $outfile (sent INTEGER, cnpj INTEGER, sendMail CHAR(10), subjectMail CHAR(120), bodyMail CHAR(400), urlReport CHAR(150), reportName CHAR(150), realReportName CHAR(150), description CHAR(250), generatedOn CHAR(16), week INTEGER, month INTEGER, year INTEGER)";

        #Cria a tabela todos os campos especificados
        $dbh->do ($query) or die LOG "ERRO: Nao foi possivel criar a tabela";
}


        LOG "Checando singularidade do relatorio";

        #Percorre o vetor pegando todas as linhas e separando pelo caracter separador
        foreach(@filesToCsv){

                #Faz o split, armazenando cada valor em sua determinada variavel
                my($sent,$cnpj,$sendMail,$subjectMail,$bodyMail,$urlReport,$reportName,$realReportName,$description,$generatedOn) = split(/$separador/,$_);

                #Verifica se o arquivo ja foi enviado para o arquivo csv, caso ja, nao devera ser adicionado novamente, para nao ter envio duplicado de arquivos. Ele fara a checagem baseado na semana ou no mes enviado, dependendo da periodicidade + cnpj
                my $sended = checkSended($cnpj, $week, $month, $outfile);

                #SE o valor de $sended for igual a 0, significa que o arquivo ainda nao foi enviado, entao, havera a insercao no arquivo.csv se nao, sera desconsiderado

                if ($sended eq '0'){

                        LOG "Inserindo entrada no arquivo csv";
                        #Insere os campos no arquivo csv
                        $dbh->do ("INSERT INTO $outfile VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", undef, $sent,$cnpj,$sendMail,$subjectMail,$bodyMail,$urlReport,$reportName,$realReportName,$description,$generatedOn,$week,$month,$year) or LOG "ERRO: Nao foi possivel inserir as informacoes no arquivo CSV: $dbh->errstr()";

                        #Insere a informacao do arquivo enviado no LOG (para eventual consulta futura
                        LOG "$reportName, localizado no path $urlReport, gerado em $generatedOn foi inserido no arquivo csv" unless ($dbh->errstr());

                }else{
                        LOG "Relatorio $reportName nao foi enviado pois ja houve envio do mesmo na periodicidade informada";
                }
        }


}

#Chama das funcoes

loginAPI();
@idConfToCsvFile = getReportConfig(getIdReports());

#Percorre o vetor, e envia o ID de configuracao daquele report para a funcao getReportInformation. Essa funcao retorna outro array com todas as informacoes do report
foreach(@idConfToCsvFile){

        #envia o id de configuracao para a funcao getReportInformation.
        my @infoReportToCsv = getReportInformation($_);

        #Envia as informacoes para a funcao que monta o CSV
        @filesToCsv = doParseCsv(@infoReportToCsv);

        #Envia o array filesToCsv para a funcao writeCsvFile
        writeCsvFile(@filesToCsv);

}