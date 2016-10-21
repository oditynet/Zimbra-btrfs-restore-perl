#!/usr/bin/perl
use POSIX qw(strftime);
use Getopt::Long qw (GetOptions);
use MIME::Base64 qw(encode_base64);

my $SNAP='/data/backup/zimbra-2016-06-27-01';
my $ACCOUNT='test@mail.zimbra.o';
my $FOLDER="/Inbox";
my $MYSQLCLIENT="/opt/zimbra/bin/mysql";
my $ZMMAILBOX="/opt/zimbra/bin/zmmailbox";
my $WORKDIR="/tmp";
my $OPERATION_MODE="";
my $onlygetmail="";
my $help="0";

my $RECOVERY=strftime "RECOVERY_%Y-%m-%d_%H%M",localtime;

GetOptions('folder=s'=> \$FOLDER, 'tmpdir=s'=> \$WORKDIR, 'snapshot=s'=> \$SNAP, 'onlycopy'=> \$OPERATION_MODE, 'account=s'=> \$ACCOUNT, 'import'=> \$onlygetmail, 'help'=> \$help) or die "Usege: $0 --help";
#Помощь
if ($help eq "1")
{
    printf "--snapshot=<path btrfs snapshot>\n";
    printf "--account=<user\@server>\n";
    printf "--folder=<Directore in E-mail. /Inbox,/Sent,/Tags>\n";
    printf "--tmpdir=<Directory>    Временная дериктория   \n";
    printf "--import                Найти только удаленные письма и импортировать их в почту\n";
    printf "--onlycopy              Найти только удаленные сообщения и скопировать их\n";
    exit 0;
}

if($onlygetmail eq "1")
{
    $onlygetmail="import";
    $OPERATION_MODE="onlycopy";
}
if ($OPERATION_MODE eq "1")
{
    $OPERATION_MODE="onlycopy";
}
printf "PATH    : %s\n",$SNAP;
printf "ACCOUNT : %s\n",$ACCOUNT;
printf "FOLDER  : %s\n",$FOLDER;
printf "RECOVERY: %s\n",$RECOVERY;
printf "DIR_TEMP: %s\n",$WORKDIR;
printf "Copy-Import: %s\n",$onlygetmail;
printf "Only COPY: %s\n",$OPERATION_MODE;
printf "\n";

if (! -d $SNAP)
{
    printf "Snapshot is not found\n";
    exit 1;
}
#Поиск пароля mysql  в снапшоте
printf "Snapshot is found\n";
$snap_mysql_pass=`cat $SNAP\'/zimbra/conf/localconfig.xml\'| tr \'\n\' \' \' | sed \'s~.*mysql_root_password\">~~\' | sed \'s~/value.*~~\' | sed \'s~<value>~~\' | sed \'s~     ~~\' | sed \'s~<~~\' `;
if ( $snap_mysql_pass eq "")
{
    printf "Passsword not found\n";
    exit 1;
}
printf "SQL password: %s \n",$snap_mysql_pass;

#Поиск ID пользователя
$mboxid=`$MYSQLCLIENT -u root -h 127.0.0.1 -P 7306 --password=$snap_mysql_pass --execute='set names "utf8";select id from zimbra.mailbox where comment="$ACCOUNT" ;'|grep -v id|tr -d '\n'`;
if ( $mboxid eq "")
{
    printf "ID in msql not found\n";
    exit 1;
}
printf "ID= %s\n",$mboxid;

#Поиск ID группы пользователя
$mboxgroup=`$MYSQLCLIENT -u root -h 127.0.0.1 -P 7306 --password=$snap_mysql_pass --execute='set names "utf8";select group_id from zimbra.mailbox where id="$mboxid" ;'|grep -v group_id|tr -d '\n'`;
if ( $mboxgroup eq "")
{
    printf "GROUP in msql not found\n";
    exit 1;
}

printf "GROUP= %s\n",$mboxgroup;

my $SNAP_ZROOT=$SNAP."/zimbra";
my $SNAP_ZDBROOT=`find $SNAP_ZROOT -maxdepth 1 -name mysql-*|tr -d '\n'`;
printf "SNAP_ZDBROOT - %s\n",$SNAP_ZDBROOT;
printf "SNAP_ZROOT - %s\n",$SNAP_ZROOT;
my $SNAP_ZDBPORT="7312";

#Удаляем временный сервер mysql из снапшота
if ( -d $WORKDIR.'/mysql')
{
    system('rm -rf '.$WORKDIR.'/mysql/*');
    printf "Deleted files in %s/mysql/*\n",$WORKDIR;
}
else{
    system('mkdir '.$WORKDIR.'/mysql');
    printf "CREATE ".$WORKDIR."/mysql\n";
}
$cp=`cp -r $SNAP_ZDBROOT/* $WORKDIR/mysql/`;
if ($cp eq "")
{
    #printf 'cp -r '.$SNAP_ZDBROOT.'/* '.$WORKDIR.'/mysql/';
    #printf "+|Copy finished\n";
}else
{
    printf "Error copy mysql BD\n";
    exit 1;
}
#Копируем БД mysql из снапшота
system('mkdir '.$WORKDIR.'/mysql/db');
system('mkdir '.$WORKDIR.'/mysql/db/data');
system('mkdir '.$WORKDIR.'/mysql/db/data/mboxgroup'.$mboxgroup);
system('mkdir '.$WORKDIR.'/mysql/db/data/mysql');
system('touch '.$WORKDIR.'/mysql/recovery-myslow.log');
system('mkdir '.$WORKDIR.'/mysql/db/data/zimbra');
system('mkdir '.$WORKDIR.'/mysql/tmp');
$cp=`cp -r $SNAP_ZROOT/db/data/mboxgroup$mboxgroup/* $WORKDIR/mysql/db/data/mboxgroup$mboxgroup/`;
$cp=`cp -r $SNAP_ZROOT/db/data/mysql/* $WORKDIR/mysql/db/data/mysql/`;
$cp=`cp -r $SNAP_ZROOT/db/data/ibdata1 $WORKDIR/mysql/db/data/ibdata1`;
$cp=`cp -r $SNAP_ZROOT/db/data/zimbra/* $WORKDIR/mysql/db/data/zimbra/`;

# Create zimbra_recovery_snap.cnf

my $cfg = <<"EOF_END";
[mysqld]
basedir      = $WORKDIR/mysql
datadir      = $WORKDIR/mysql/db/data
socket       = $WORKDIR/mysql/mysql.sock
pid-file     = $WORKDIR/mysql/mysql.pid
bind-address = 127.0.0.1
port         = $SNAP_ZDBPORT
user         = root
tmpdir       = $WORKDIR/mysql/tmp

max_allowed_packet = 16777216
slow_query_log_file = /tmp/mysql/myslow.log
slow_query_log = 1
plugin-load = innodb=ha_innodb_plugin.so;innodb_trx=ha_innodb_plugin.so;innodb_locks=ha_innodb_plugin.so;innodb_lock_waits=ha_innodb_plugin.so;innodb_cmp=ha_innodb_plugin.so;innodb_cmp_reset=ha_innodb_plugin.so;innodb_cmpmem=ha_innodb_plugin.so;innodb_cmpmem_reset=ha_innodb_plugin.so
ignore-builtin-innodb
external-locking
long-query-time  = 1
log-queries-not-using-indexes
thread_cache_size = 110
max_connections   = 110
query_cache_type = 0
sort_buffer_size = 1048576
read_buffer_size = 1048576
table_cache = 1200
innodb_buffer_pool_size        = 1292461670
innodb_log_file_size = 52428800
innodb_log_buffer_size         = 8388608
innodb_file_per_table
innodb_open_files              = 2710
innodb_max_dirty_pages_pct = 30
innodb_flush_method            = O_DIRECT
innodb_flush_log_at_trx_commit = 0
[mysqld_safe]
err-log      = /var/log/mysqld-snap.log
pid-file     = $WORKDIR/mysql/snap/mysql.pid
EOF_END


#записать новый конфигурационный файл mysql в файл
my $filename=$WORKDIR.'/mysql/zimbra_recovery_snap.cnf';
open(my $fh,'>', $filename) or die "-|Cannot open file";
print $fh $cfg;
close $fh;

printf "Start temp mysql\n";
$sFOLDER=`echo $FOLDER|sed 's~.*/~~'|tr -d '\n'`;

#Создаем отдельный поток для временной БД mysql
my $newchild = fork();
if (! $newchild)
{
    $start_mysql = system($WORKDIR.'/mysql/libexec/mysqld --defaults-file='.$WORKDIR.'/mysql/zimbra_recovery_snap.cnf --basedir='.$WORKDIR.'/mysql --datadir='.$WORKDIR.'/mysql/db/data --slow_query_log_file='.$WORKDIR.'/mysql/recovery-myslow.log --tmpdir '.$WORKDIR.'/mysql --read-only --port='.$SNAP_ZDBPORT.' -u root 2> /dev/null &');
}
else
{
    #Ожидание запуска временной БД
    $sqlstat=`netstat -lnpt|grep $SNAP_ZDBPORT|cut -f1 -d/`;
    while($sqlstat eq "")
    {
	$sqlstat=`netstat -lnpt|grep $SNAP_ZDBPORT|cut -f1 -d/`;
	print ".";
	sleep 1;
    }
    my @awk= split(/\s+/, $sqlstat);
    printf "\nStatus process mysql: %s\n",$awk[-1];

    $zmsg_catid=`$MYSQLCLIENT -u root -h 127.0.0.1 -P $SNAP_ZDBPORT --password=$snap_mysql_pass --execute="SET NAMES 'utf8';use mboxgroup$mboxgroup;SELECT id FROM mail_item where name='$sFOLDER' and mailbox_id=$mboxid and type=1 limit 1;"|grep -v id|tr -d '\n'`;
    printf "SQL temp return: %s\n",$zmsg_catid;
    $zmsg_names=`$MYSQLCLIENT -u root -h 127.0.0.1 -P $SNAP_ZDBPORT --password=$snap_mysql_pass --execute="SET NAMES 'utf8';use mboxgroup$mboxgroup;SELECT name FROM mail_item where mailbox_id=$mboxid and type=1;"|grep -v name`;#|sed 's~ ~\`~'`;
    printf "In the snapshot contain FOLDER :\n %s\n",$zmsg_names;
    if ($zmsg_catid eq "")
    {
	printf "-|Catalog %s not fount in the shapshot\n",$FOLDER;
    }else
    {
	printf "+|Catalog %s  fount in the shapshot(id=%s)\n",$FOLDER,$zmsg_catid;
	@zmsg_snap_array=`$MYSQLCLIENT -u root -h 127.0.0.1 -P $SNAP_ZDBPORT --password=$snap_mysql_pass --execute="SET NAMES 'utf8';use mboxgroup$mboxgroup;SELECT id FROM mail_item where mailbox_id=$mboxid and type=5 and folder_id=$zmsg_catid;"|grep -v id`;
    }

    #режим поиска только удаленных сообщений
    if ($OPERATION_MODE eq "onlycopy")
    {
        printf "Find only deleted messages\n";
        $zimbra_folder_id=`$MYSQLCLIENT -u root -h 127.0.0.1 -P 7306 --password=$snap_mysql_pass --execute="SET NAMES 'utf8';use mboxgroup$mboxgroup;SELECT id FROM mail_item where name='$sFOLDER' and mailbox_id=$mboxid and type=1 limit 1;"|grep -v id`;
        printf "In real server FOLDER ID: %s\n",$zimbra_folder_id;
        $zimbra_folder_messages=`$MYSQLCLIENT -u root -h 127.0.0.1 -P 7306 --password=$snap_mysql_pass --execute="SET NAMES 'utf8';use mboxgroup$mboxgroup;SELECT id FROM mail_item where mailbox_id=$mboxid and type=5 and folder_id=$zimbra_folder_id;"|grep -v id|tr  '\n' ' '`;
	#Нашли только удаленных писем в почте у пользователя и добавление их в массив для дальнейшего восстановления/копирования
        printf "In real server ID messages:\n %s\n",$zimbra_folder_messages;
	@zimbra_diff=();
                foreach $zmsg_unit (@zmsg_snap_array)
        {
    	    $b=`echo "$zmsg_unit"|tr -d '\n'|tr -d '\n'`;
    	    $z_check=`echo $zimbra_folder_messages|egrep $b`;
    	        	    if($z_check eq "")
    	    {
    		push(@zimbra_diff,$zmsg_unit);
    		print "<";
    	    }
        }
        $zimbra_diff_count=@zimbra_diff;
        printf "\n+|In folder \"%s\" fount %s messages\n",$sFOLDER,$zimbra_diff_count;
    }
    $zmsg_count=@zimbra_diff;
    printf "+|In snapshot found %s messages in folder IMAP %s%s\n",$zmsg_count,$ACCOUNT,$FOLDER;

    # Во временной папке создаем директорию куда будем копировать восстанавливаемые письма
    system('mkdir '.$WORKDIR.'/'.$RECOVERY);
    if ( -d $WORKDIR.'/'.$RECOVERY)
    {
	printf "+|Create folder %s/%s\n",$ACCOUNT,$RECOVERY;
    }else
    {
	printf "-|Folder is not create %s\n",$RECOVERY;
	exit 1;
    }
    printf "Process copy messages %s in %s\n",$zmsg_count,$WORKDIR."/$RECOVERY/";
    foreach $zmsg_real (@zimbra_diff)
    {
	$zmsg_real=`echo "$zmsg_real"|tr -d '\n'|tr -d '\n'`;
	print ">";
	# Поиск писем в снапшоте по ID и копирование их во временную папку
	$filepath=`find $SNAP_ZROOT/store/0/$mboxid/msg/ -name '$zmsg_real-*'|tr -d '\n'|tr -d '\n'`;
	system("cp $filepath $WORKDIR/$RECOVERY/");
    }
    # Если выбран режим не просто копирования удаленных писем во временную папку,но и импорт ее в почту
    if($onlygetmail ne "import")
    {
	printf "\n-|Import messanges for user is OFF\n";
    } elsif ($zimbra_diff_count != 0)
    {
	printf "\n+|Import %s messanger in Zimbra for %s\n",$zmsg_count,$ACCOUNT;
	my $item="";
	my $cont="";
	$FOLDER_DATE=$RECOVERY;
	$FOLDER_DATE_PATH="/RECOVERY/".$RECOVERY;

	printf "?|Are you want import in Zimbra?(yes/no)";
	$item=<STDIN>;
	chomp($item);
	# Если не хотите,то останавливает поток со временной БД и выходим.
	if ($item eq "no")
	{
	    $item="no";
	    $cont="no";
	    if ( -d $WORKDIR.'/'.$RECOVERY)
	    {
    	        system('rm -rf '.$WORKDIR.'/'.$RECOVERY.'/*');
    		printf "+|Deleted files in %s/$s*\n",$WORKDIR,$RECOVERY;
    	    }
	    $kill_mysql=`netstat -lnp|grep $SNAP_ZDBPORT|awk '{print $7}'|cut -f1 -d/|xargs  kill `;
	    exit 0;
	    
	}
	if ($item eq "yes")
	{
	    $cont="Yes";
	}
	if($cont eq "Yes")
	{
	# Проверяем наличие в почте папки RECOVERY и в случае ее отсутствии создаем
	    @zimbra_folder_list=`$MYSQLCLIENT -u root -h 127.0.0.1 -P 7306 --password=$snap_mysql_pass --execute="SET NAMES 'utf8';use mboxgroup$mboxgroup;SELECT subject FROM mail_item where mailbox_id=$mboxid and type=1;"|grep -v subject|tr '\n' ' '|tr '\n' ' '`;
	    $zimbra_recovery_check=`echo "@zimbra_folder_list"|grep RECOVERY|tr -d '\n'|tr -d '\n'`;
	    if($zimbra_recovery_check eq "")
	    {
		printf "+|Create folder in Zimbra at user\n";
		$zimbra_reply=`$ZMMAILBOX -z -m $ACCOUNT createFolder -V message /RECOVERY|tr -d '\n'`;
		printf "Zimbra say: %s\n",$zimbra_reply;
	    }
	    {
		print "+| RECOVERY folder isn't create\n";
	    }
	    $zimbra_folder_check="";
	    $a=`echo "@zimbra_folder_list"|grep $FOLDER_DATE|tr -d '\n'|tr -d '\n'|tr -d '\n'`;
	    #printf "FOLDER: %s\n",$a;
	    if ($a ne "")
	    {
	        $zimbra_folder_check="exists";
	        #printf "++++ %s",$FOLDER_DATE;
	    }
	    # Условие по созданию в папке RECOVERY подпапок определенного формата, а если аткая подпапка есть,то создавать такую же с приставкой (1,2,3,...)
	    if($zimbra_folder_check ne "")
	    {
		$i=1;
		while ($zimbra_folder_check ne "") 
		{
		    if(`echo "@zimbra_folder_list"|grep "$FOLDER_DATE($i)"|tr -d '\n'|tr -d '\n'` ne "")
    		    {
    		        $zimbra_folder_check="exists";
    			#printf "**** %s\n",$i;
		    }else
		    {
		        $zimbra_folder_check="";
		        #printf "----- %s\n",$FOLDER_DATE."(".$i.")";
		        #printf "A- %s\n",$a;
		    }
		    if($zimbra_folder_check eq "")
			{
			    printf "+|Create folder in Zimbra at user\n";
			    $zimbra_reply=`$ZMMAILBOX -z -m $ACCOUNT createFolder -V message $FOLDER_DATE_PATH"\("$i")\"|tr -d '\n'`;
			    printf "Zimbra say: %s\n",$zimbra_reply;
			}
			else
			{
			    $i++;
			}
		    }
		    $FOLDER_DATE="$FOLDER_DATE($i)";
		    $FOLDER_DATE_PATH="RECOVERY/$FOLDER_DATE";
	    } else
	    {
		printf "+|I can create  folder in Zimbra at user\n";
		$zimbra_reply=`$ZMMAILBOX -z -m $ACCOUNT createFolder -V message $FOLDER_DATE_PATH|tr -d '\n'`;
		print "$ZMMAILBOX -z -m $ACCOUNT createFolder -V message $FOLDER_DATE_PATH\n";
		printf "Zimbra say: %s\n",$zimbra_reply;
	    }
	}
	# Сам процесс импортирования почты из временной папки в почту пользователя
	if($cont eq "Yes")
	{
	    printf "+|Import message in Folder $s\n",$FOLDER_DATE;
	    $zimbra_reply=`$ZMMAILBOX -z -m $ACCOUNT addMessage "$FOLDER_DATE_PATH" $WORKDIR/$RECOVERY/*`;
	    
	}
    }
    $item="";
    # Удалить файлы из временной папки или оставить
    printf "?|Are you want delete temp path?(yes/no)";
    $item=<STDIN>;
    chomp($item);
    if ($item eq "yes")
    {
	if ( -d $WORKDIR.'/'.$RECOVERY)
	{
    	    system('rm -rf '.$WORKDIR.'/'.$RECOVERY.'/*');
    	    printf "Deleted files in %s/$s*\n",$WORKDIR,$RECOVERY;
    	}
    }
}

$kill_mysql=`netstat -lnp|grep $SNAP_ZDBPORT|awk '{print $7}'|cut -f1 -d/|xargs  kill `;
printf "MYSQL temp stop: %s\n",$kill_mysql;
exit 0;
