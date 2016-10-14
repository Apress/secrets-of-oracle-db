#!/usr/bin/env perl

=for commentary

RCS $Id: esqltrcprof.pl,v 1.29 2008/05/18 19:32:12 ndebes Exp $

 written by Norbert Debes, Munich, Germany

 Change History
 - Fixed trace file level accouting for CPU time (had forgotten to avoid double counting at dependency level > 0 ). No changes required at statement level.
 todo: average rows fetched, single row fetches, mutli-row fetches
 is SQL*Net more data from client a round-trip? I think so.
 wait time per latch (had additional info for event "latch free", less relevant in 10g due to latch: ... wait events
 calculate elapsed time per module and action using time stamps after ACTION NAME, etc.
 turn into module
 retrieve index and column information on tables in trace use ORADBB module
 the same statement might be run at dep=0 and at dep=1, so don't save dep with stmt
 a separate section without aggregation in chronological order showing dependencies
 is probably appropriate
 statement as percentage of R
 map numeric optimizer goal to text
 latch names in 9i: unterschiedlich zwischen 9.2.0.?
 exec to parse ratio
 add debug flag
 10g WAIT hat auch tim=
 evtl. kann man durch Ausführung mit cursor_sharing=force statement ohne bind variablen finden.
 connect als dba und prepare mit alter session set current_schema
 oder ersetzen von zahlen und strings durch bind variablen im statement und dann
 vergleichen, wie oft statement vorhanden ist
 look at #STAT and PARSING
 Idee: um nicht auf DBI angewiesen zu sein, könnte ich auch SQL Skript generieren,
 das weitere Infos aus der DB zieht
 rekursiv verbrauchte Zeit wird bei dep=0 Anweisung draufgeschlagen. 
 evtl. SQL Anweisungen nach Kosten sortieren
 - Die elapsed time e eines database call (z.B. FETCH) beinhaltet die elapsed time ela der wait events, die der
 database call verursacht hat. D.h. um die elapsed time des FETCH zu bekommen, muss man die elapsed times der
 wait events wegen des FETCH abziehen
 - total response time= time spent in database calls + time spent between database calls (only SQL*Net message?)
 - double counting von rekursivem SQL. Ausgabe wiederum bei Fertigstellung, d.h. rekursive Anweisungen stehen
 vor denen mit dep=0
 könnte berechnen: recursive user CPU, recursive SYSTEM CPU, dasselbe mit elpased time
 minimum and max. duration per event
 Bugs:
 the program does not take the rare possibility that two different statements might have
 the same hash value into account
 --------
 possible future enhancements:
aggregation of shareable SQL

    Applications that don't use bind variables are particularly troublesome to diagnose with traditional tools like tkprof or trcanalyzer, where one bind variable mistake can show up in your output as twenty thousand distinct problems with individual contributions of 0.005% of your response time. 
accounting of recursive SQL relationships

    Sometimes recursive SQL is the cause of a performance problem. When it is, you need to know the relationship that the recursive statements have to your application code. Oracle's SQL trace files contain all the information you need to see that relationship. 
          SQL statement text formatted for easier reading
          Histograms for wait events (I/O, latch, enqueue, etc.) to reveal information about skew in operation durations
          Statement-level statistics shown both inclusive and exclusive of recursive SQL (tkprof shows only one; which one varies by release)
          Identification of which PIO blocks are managed through the Oracle buffer cache and which are not
          Statement-level statistics shown in per-execute and per-returned-row form 

=cut

printf "ESQLTRCPROF %s (%s)\n", substr(q{$Revision: 1.29 $},1,15), substr(q{$Date: 2008/05/18 19:32:12 $},1,25);


my $debug_level=0;
# supported debug levels: 1
my $debug_env_var="ESQLTRCPROF_DEBUG";
if ( defined($ENV{$debug_env_var}) && $ENV{$debug_env_var} > 0) {
	$debug_level=$ENV{$debug_env_var};
	printf ("Debugging level ($debug_env_var)=%d\n", $debug_level);
}

use strict;
use warnings;
use Getopt::Std;
use Math::BigInt; # for tim values which are very large due to microsecond resolution

# the same statement may appear with different cursor numbers
# if generating a chronological marked up trace, link by hash value

my $counter=0;
use constant {
        TEXT   => $counter++, # statement text (multi-line)
        HARD_PARSE_COUNT  => $counter++, # all integers from here
        SOFT_PARSE_COUNT  => $counter++,
        PARSE_COUNT  => $counter++,
        EXEC_COUNT  => $counter++,
        FETCH_COUNT  => $counter++,
        PARSE_ELAPSED  => $counter++,
        EXEC_ELAPSED  => $counter++,
        FETCH_ELAPSED  => $counter++,
        PARSE_CPU  => $counter++,
        EXEC_CPU  => $counter++,
        FETCH_CPU  => $counter++,
        PARSE_DISK  => $counter++,
        EXEC_DISK  => $counter++,
        FETCH_DISK  => $counter++,
        PARSE_CR  => $counter++,
        EXEC_CR  => $counter++,
        FETCH_CR  => $counter++,
        PARSE_CUR_READ  => $counter++,
        EXEC_CUR_READ  => $counter++,
        FETCH_CUR_READ  => $counter++,
        PARSE_ROWS  => $counter++,
        EXEC_ROWS  => $counter++,
        FETCH_ROWS  => $counter++,
        OPT_GOAL  => $counter++,
        TOTAL_E_PARSE_EXEC_FETCH  => $counter++, # sum of e for PARSE,EXEC, FETCH
        TOTAL_ELAPSED  => $counter++, # sum of e for PARSE, EXEC, FETCH plus wait events not rolled up in PARSE, EXEC, FETCH. At a minimum these are SQL*Net message from/to client, other candidate is direct path read/write
        WAIT_ELA  => $counter++,  # reference to a hash
        WAIT_COUNT  => $counter++,  # reference to a hash
        STAT  => $counter++, # multi-line text
        SQL_ID  => $counter++, # 11g+ sqlid from PARSING IN CURSOR
        MODULE  => $counter++, # instrumentation: MODULE
        ACTION  => $counter++, # instrumentation: ACTION
        DEP  => $counter++, # dependency level
    };

my %ela;
my %latch_free_waits;
my %latch_sleeps;
my %enqueue_waits;
my %enqueue_wait_time;
my $enqueue_name;
my $lock_mode;

# mapping cursor number to hash value
my %cursor_to_hv;
# hash of hashes for holding all statements
my %stmt_list;
# variables for parse,etc.
my ($stmt_type, $cpu, $elapsed, $disk, $cr, $cur_read, $miss, $rows, $opt_goal, $tim);
# for PARSING IN
my($dep, $user_id, $ora_cmd_type, $perm_user_id, $hash_value, $address, $stmt_text, $line, $sqlid);
$sqlid='undefined';
# variables for wait event
my ($cursor_nr, $event_name, $ela_time, $p1_text, $p1_value, $p2_text, $p2_value, $p3_text, $p3_value, $obj_id);
# variables for STAT
my ($id, $cnt, $pid, $pos, $row_source, $obj_info);

my %opt_goal_mapping;

# cursor 0 never has a PARSING in cursor or PARSE, EXEC, FETCH. must be treated specially
my $unknown_cursor_nr=0;

my @indentation;
# parent 0 of plan has no indentation
$indentation[0]=0;
# STAT line with id=1 always has one blank indentation, no need to execute this repeatedly
$indentation[1]=1;

my %occurrences;
$occurrences{"PARSE"}=0;
$occurrences{"EXEC"}=0;
$occurrences{"FETCH"}=0; 
$occurrences{"think time"}=0;
$occurrences{"SQL*Net message from client"}=0;
my %ela_per_action;
my %physical_reads;
$physical_reads{sequential}=0;
$physical_reads{scattered}=0;
# would get 'Use of uninitialized value in addition'
# below if think time is not initialized to 0 and no think time is found
#$ela{"think time"}=0;
$ela_per_action{"parse CPU"}=0;
$ela_per_action{"exec CPU"}=0;
$ela_per_action{"fetch CPU"}=0;
my $sum_ela=0;
# response time R
my $R=0;
my $avg_sql_net_msg_from_client=0;
my ($t0,$t1)=(new Math::BigInt->bzero(),new Math::BigInt->bzero()); # first and last time stamps in trace file
# current dependency level dep
my ($physical_reads, $consistent_gets, $db_block_gets, $cursor_misses, $cursor_hits, $rows_processed)=(0,0,0,0,0,0);
# counters for XCTEND, i.e. commit and rollback after transaction or no tx
# that is read only access, ro: read only, rw: read write=tx was open
my ($commit_rw, $commit_ro, $rollback_rw, $rollback_ro)=(0, 0, 0, 0);

=for commentary 

application instrumentation, default module and action name is undefined
use the same code as for per statement accounting

=cut

my ($curr_app_mod, $curr_app_act)=("undefined", "undefined");
my %ela_per_app_mod;
my %ela_per_app_mod_act;

# initialize mapping from latch numbers to latch names
# generated with this SQL statement: 
=for commentary 

set pages 0
set echo off
set verify off
define release=11gR1
spool latch_mapping.pl
select '$latch_name_&release{' || latch#||'}=q{' || name||'};' from v$latchname;
spool off

=cut

my %latch_name_9i;
$latch_name_9i{0}=q{latch wait list};                                           
$latch_name_9i{1}=q{event range base latch};                                    
$latch_name_9i{2}=q{post/wait queue};                                           
$latch_name_9i{3}=q{process allocation};                                        
$latch_name_9i{4}=q{session allocation};                                        
$latch_name_9i{5}=q{session switching};                                         
$latch_name_9i{6}=q{process group creation};                                    
$latch_name_9i{7}=q{session idle bit};                                          
$latch_name_9i{8}=q{longop free list parent};                                   
$latch_name_9i{9}=q{cached attr list};                                          
$latch_name_9i{10}=q{object stats modification};                                
$latch_name_9i{11}=q{Testing};                                                  
$latch_name_9i{12}=q{shared java pool};                                         
$latch_name_9i{13}=q{latch for background adjusted parameters};                 
$latch_name_9i{14}=q{event group latch};                                        
$latch_name_9i{15}=q{messages};                                                 
$latch_name_9i{16}=q{enqueues};                                                 
$latch_name_9i{17}=q{enqueue hash chains};                                      
$latch_name_9i{18}=q{instance enqueue};                                         
$latch_name_9i{19}=q{trace latch};                                              
$latch_name_9i{20}=q{FOB s.o list latch};                                       
$latch_name_9i{21}=q{FIB s.o chain latch};                                      
$latch_name_9i{22}=q{KSFQ};                                                     
$latch_name_9i{23}=q{X$KSFQP};                                                  
$latch_name_9i{24}=q{i/o slave adaptor};                                        
$latch_name_9i{25}=q{ksfv messages};                                            
$latch_name_9i{26}=q{msg queue latch};                                          
$latch_name_9i{27}=q{done queue latch};                                         
$latch_name_9i{28}=q{session queue latch};                                      
$latch_name_9i{29}=q{direct msg latch};                                         
$latch_name_9i{30}=q{vecio buf des};                                            
$latch_name_9i{31}=q{ksfv subheap};                                             
$latch_name_9i{32}=q{resmgr group change latch};                                
$latch_name_9i{33}=q{channel handle pool latch};                                
$latch_name_9i{34}=q{channel operations parent latch};                          
$latch_name_9i{35}=q{message pool operations parent latch};                     
$latch_name_9i{36}=q{channel anchor};                                           
$latch_name_9i{37}=q{dynamic channels};                                         
$latch_name_9i{38}=q{first spare latch};                                        
$latch_name_9i{39}=q{second spare latch};                                       
$latch_name_9i{40}=q{ksxp tid allocation};                                      
$latch_name_9i{41}=q{segmented array pool};                                     
$latch_name_9i{42}=q{granule operation};                                        
$latch_name_9i{43}=q{KSXR large replies};                                       
$latch_name_9i{44}=q{SGA mapping latch};                                        
$latch_name_9i{45}=q{ges process table freelist};                               
$latch_name_9i{46}=q{ges process parent latch};                                 
$latch_name_9i{47}=q{ges process hash list};                                    
$latch_name_9i{48}=q{ges resource table freelist};                              
$latch_name_9i{49}=q{ges caches resource lists};                                
$latch_name_9i{50}=q{ges resource hash list};                                   
$latch_name_9i{51}=q{ges resource scan list};                                   
$latch_name_9i{52}=q{ges s-lock bitvec freelist};                               
$latch_name_9i{53}=q{ges enqueue table freelist};                               
$latch_name_9i{54}=q{ges timeout list};                                         
$latch_name_9i{55}=q{ges deadlock list};                                        
$latch_name_9i{56}=q{ges statistic table};                                      
$latch_name_9i{57}=q{ges synchronous data};                                     
$latch_name_9i{58}=q{KJC message pool free list};                               
$latch_name_9i{59}=q{KJC receiver ctx free list};                               
$latch_name_9i{60}=q{KJC snd proxy ctx free list};                              
$latch_name_9i{61}=q{KJC destination ctx free list};                            
$latch_name_9i{62}=q{KJC receiver queue access list};                           
$latch_name_9i{63}=q{KJC snd proxy queue access list};                          
$latch_name_9i{64}=q{KJC global post event buffer};                             
$latch_name_9i{65}=q{KJCT receiver queue access};                               
$latch_name_9i{66}=q{KJCT flow control latch};                                  
$latch_name_9i{67}=q{ges domain table};                                         
$latch_name_9i{68}=q{ges group table};                                          
$latch_name_9i{69}=q{ges group parent};                                         
$latch_name_9i{70}=q{gcs resource hash};                                        
$latch_name_9i{71}=q{gcs opaque info freelist};                                 
$latch_name_9i{72}=q{gcs resource freelist};                                    
$latch_name_9i{73}=q{gcs resource scan list};                                   
$latch_name_9i{74}=q{gcs shadows freelist};                                     
$latch_name_9i{75}=q{name-service entry};                                       
$latch_name_9i{76}=q{name-service request queue};                               
$latch_name_9i{77}=q{name-service pending queue};                               
$latch_name_9i{78}=q{name-service namespace bucket};                            
$latch_name_9i{79}=q{name-service memory objects};                              
$latch_name_9i{80}=q{name-service namespace objects};                           
$latch_name_9i{81}=q{name-service request};                                     
$latch_name_9i{82}=q{ges struct kjmddp};                                        
$latch_name_9i{83}=q{gcs partitioned table hash};                               
$latch_name_9i{84}=q{gcs pcm hashed value bucket hash};                         
$latch_name_9i{85}=q{gcs partitioned freelist};                                 
$latch_name_9i{86}=q{gcs remaster request queue};                               
$latch_name_9i{87}=q{file number translation table};                            
$latch_name_9i{88}=q{mostly latch-free SCN};                                    
$latch_name_9i{89}=q{lgwr LWN SCN};                                             
$latch_name_9i{90}=q{redo on-disk SCN};                                         
$latch_name_9i{91}=q{Consistent RBA};                                           
$latch_name_9i{92}=q{batching SCNs};                                            
$latch_name_9i{93}=q{cache buffers lru chain};                                  
$latch_name_9i{94}=q{buffer pool};                                              
$latch_name_9i{95}=q{multiple dbwriter suspend};                                
$latch_name_9i{96}=q{active checkpoint queue latch};                            
$latch_name_9i{97}=q{checkpoint queue latch};                                   
$latch_name_9i{98}=q{cache buffers chains};                                     
$latch_name_9i{99}=q{cache buffer handles};                                     
$latch_name_9i{100}=q{multiblock read objects};                                 
$latch_name_9i{101}=q{cache protection latch};                                  
$latch_name_9i{102}=q{simulator lru latch};                                     
$latch_name_9i{103}=q{simulator hash latch};                                    
$latch_name_9i{104}=q{sim partition latch};                                     
$latch_name_9i{105}=q{state object free list};                                  
$latch_name_9i{106}=q{LGWR NS Write};                                           
$latch_name_9i{107}=q{archive control};                                         
$latch_name_9i{108}=q{archive process latch};                                   
$latch_name_9i{109}=q{managed standby latch};                                   
$latch_name_9i{110}=q{FAL subheap alocation};                                   
$latch_name_9i{111}=q{FAL request queue};                                       
$latch_name_9i{112}=q{alert log latch};                                         
$latch_name_9i{113}=q{redo writing};                                            
$latch_name_9i{114}=q{redo copy};                                               
$latch_name_9i{115}=q{redo allocation};                                         
$latch_name_9i{116}=q{OS file lock latch};                                      
$latch_name_9i{117}=q{KCL instance latch};                                      
$latch_name_9i{118}=q{KCL gc element parent latch};                             
$latch_name_9i{119}=q{KCL name table parent latch};                             
$latch_name_9i{120}=q{KCL freelist parent latch};                               
$latch_name_9i{121}=q{KCL bast context freelist latch};                         
$latch_name_9i{122}=q{loader state object freelist};                            
$latch_name_9i{123}=q{begin backup scn array};                                  
$latch_name_9i{124}=q{Managed Standby Recovery State};                          
$latch_name_9i{125}=q{TLCR context};                                            
$latch_name_9i{126}=q{TLCR meta context};                                       
$latch_name_9i{127}=q{logical standby cache};                                   
$latch_name_9i{128}=q{Media rcv so alloc latch};                                
$latch_name_9i{129}=q{parallel recoverable recovery};                           
$latch_name_9i{130}=q{block media rcv so alloc latch};                          
$latch_name_9i{131}=q{mapped buffers lru chain};                                
$latch_name_9i{132}=q{dml lock allocation};                                     
$latch_name_9i{133}=q{list of block allocation};                                
$latch_name_9i{134}=q{transaction allocation};                                  
$latch_name_9i{135}=q{dummy allocation};                                        
$latch_name_9i{136}=q{transaction branch allocation};                           
$latch_name_9i{137}=q{commit callback allocation};                              
$latch_name_9i{138}=q{sort extent pool};                                        
$latch_name_9i{139}=q{undo global data};                                        
$latch_name_9i{140}=q{ktm global data};                                         
$latch_name_9i{141}=q{parallel txn reco latch};                                 
$latch_name_9i{142}=q{intra txn parallel recovery};                             
$latch_name_9i{143}=q{resumable state object};                                  
$latch_name_9i{144}=q{sequence cache};                                          
$latch_name_9i{145}=q{temp lob duration state obj allocation};                  
$latch_name_9i{146}=q{row cache enqueue latch};                                 
$latch_name_9i{147}=q{row cache objects};                                       
$latch_name_9i{148}=q{dictionary lookup};                                       
$latch_name_9i{149}=q{cost function};                                           
$latch_name_9i{150}=q{user lock};                                               
$latch_name_9i{151}=q{global ctx hash table latch};                             
$latch_name_9i{152}=q{comparison bit cache};                                    
$latch_name_9i{153}=q{instance information};                                    
$latch_name_9i{154}=q{policy information};                                      
$latch_name_9i{155}=q{global tx hash mapping};                                  
$latch_name_9i{156}=q{shared pool};                                             
$latch_name_9i{157}=q{library cache};                                           
$latch_name_9i{158}=q{library cache pin};                                       
$latch_name_9i{159}=q{library cache pin allocation};                            
$latch_name_9i{160}=q{library cache load lock};                                 
$latch_name_9i{161}=q{Token Manager};                                           
$latch_name_9i{162}=q{Direct I/O Adaptor};                                      
$latch_name_9i{163}=q{cas latch};                                               
$latch_name_9i{164}=q{rm cas latch};                                            
$latch_name_9i{165}=q{resmgr:runnable lists};                                   
$latch_name_9i{166}=q{resmgr:actses change state};                              
$latch_name_9i{167}=q{resmgr:actses change group};                              
$latch_name_9i{168}=q{resmgr:session queuing};                                  
$latch_name_9i{169}=q{resmgr:actses active list};                               
$latch_name_9i{170}=q{resmgr:schema config};                                    
$latch_name_9i{171}=q{resmgr:gang list};                                        
$latch_name_9i{172}=q{resmgr:queued list};                                      
$latch_name_9i{173}=q{resmgr:running actses count};                             
$latch_name_9i{174}=q{resmgr:vc list latch};                                    
$latch_name_9i{175}=q{resmgr:method mem alloc latch};                           
$latch_name_9i{176}=q{resmgr:plan CPU method};                                  
$latch_name_9i{177}=q{resmgr:resource group CPU method};                        
$latch_name_9i{178}=q{QMT};                                                     
$latch_name_9i{179}=q{dispatcher configuration};                                
$latch_name_9i{180}=q{session timer};                                           
$latch_name_9i{181}=q{parameter list};                                          
$latch_name_9i{182}=q{presentation list};                                       
$latch_name_9i{183}=q{address list};                                            
$latch_name_9i{184}=q{end-point list};                                          
$latch_name_9i{185}=q{virtual circuit buffers};                                 
$latch_name_9i{186}=q{virtual circuit queues};                                  
$latch_name_9i{187}=q{virtual circuits};                                        
$latch_name_9i{188}=q{kmcptab latch};                                           
$latch_name_9i{189}=q{kmcpvec latch};                                           
$latch_name_9i{190}=q{JOX SGA heap latch};                                      
$latch_name_9i{191}=q{job_queue_processes parameter latch};                     
$latch_name_9i{192}=q{job workq parent latch};                                  
$latch_name_9i{193}=q{child cursor hash table};                                 
$latch_name_9i{194}=q{query server process};                                    
$latch_name_9i{195}=q{query server freelists};                                  
$latch_name_9i{196}=q{error message lists};                                     
$latch_name_9i{197}=q{process queue};                                           
$latch_name_9i{198}=q{process queue reference};                                 
$latch_name_9i{199}=q{parallel query stats};                                    
$latch_name_9i{200}=q{parallel query alloc buffer};                             
$latch_name_9i{201}=q{hash table modification latch};                           
$latch_name_9i{202}=q{hash table column usage latch};                           
$latch_name_9i{203}=q{constraint object allocation};                            
$latch_name_9i{204}=q{device information};                                      
$latch_name_9i{205}=q{temporary table state object allocation};                 
$latch_name_9i{206}=q{internal temp table object number allocation latch};      
$latch_name_9i{207}=q{SQL memory manager latch};                                
$latch_name_9i{208}=q{SQL memory manager workarea list latch};                  
$latch_name_9i{209}=q{ncodef allocation latch};                                 
$latch_name_9i{210}=q{NLS data objects};                                        
$latch_name_9i{211}=q{numer of job queues for server notfn};                    
$latch_name_9i{212}=q{message enqueue sync latch};                              
$latch_name_9i{213}=q{bufq subscriber channel};                                 
$latch_name_9i{214}=q{non-pers queues instances};                               
$latch_name_9i{215}=q{queue sender's info. latch};                              
$latch_name_9i{216}=q{browsers latch};                                          
$latch_name_9i{217}=q{enqueue buffered messages latch};                         
$latch_name_9i{218}=q{dequeue sob latch};                                       
$latch_name_9i{219}=q{spilled messages latch};                                  
$latch_name_9i{220}=q{spilled msgs queues list latch};                          
$latch_name_9i{221}=q{dynamic channels context latch};                          
$latch_name_9i{222}=q{image handles of buffered messages latch};                
$latch_name_9i{223}=q{kwqit: protect wakeup time};                              
$latch_name_9i{224}=q{KWQP Prop Status};                                        
$latch_name_9i{225}=q{AQ Propagation Scheduling Proc Table};                    
$latch_name_9i{226}=q{AQ Propagation Scheduling System Load};                   
$latch_name_9i{227}=q{process};                                                 
$latch_name_9i{228}=q{fixed table rows for x$hs_session};                       
$latch_name_9i{229}=q{qm_init_sga};                                             
$latch_name_9i{230}=q{XDB unused session pool};                                 
$latch_name_9i{231}=q{XDB used session pool};                                   
$latch_name_9i{232}=q{XDB Config};                                              
$latch_name_9i{233}=q{DMON Process Context Latch};                              
$latch_name_9i{234}=q{DMON Work Queues Latch};                                  
$latch_name_9i{235}=q{RSM process latch};                                       
$latch_name_9i{236}=q{RSM SQL latch};                                           
$latch_name_9i{237}=q{Request id generation latch};                             
$latch_name_9i{238}=q{xscalc freelist};                                         
$latch_name_9i{239}=q{xssinfo freelist};                                        
$latch_name_9i{240}=q{AW SGA latch};                                            

# 10g Release1 latch number to latch name mapping
my %latch_name_10gR1;
$latch_name_10gR1{0}=q{latch wait list};
$latch_name_10gR1{1}=q{event range base latch};
$latch_name_10gR1{2}=q{post/wait queue};
$latch_name_10gR1{3}=q{process allocation};
$latch_name_10gR1{4}=q{session allocation};
$latch_name_10gR1{5}=q{session switching};
$latch_name_10gR1{6}=q{process group creation};
$latch_name_10gR1{7}=q{session idle bit};
$latch_name_10gR1{8}=q{client/application info};
$latch_name_10gR1{9}=q{longop free list parent};
$latch_name_10gR1{10}=q{foreground creation};
$latch_name_10gR1{11}=q{ksuosstats global area};
$latch_name_10gR1{12}=q{ksupkttest latch};
$latch_name_10gR1{13}=q{cached attr list};
$latch_name_10gR1{14}=q{object stats modification};
$latch_name_10gR1{15}=q{Testing};
$latch_name_10gR1{16}=q{parameter table allocation management};
$latch_name_10gR1{17}=q{event group latch};
$latch_name_10gR1{18}=q{messages};
$latch_name_10gR1{19}=q{enqueues};
$latch_name_10gR1{20}=q{enqueue hash chains};
$latch_name_10gR1{21}=q{instance enqueue};
$latch_name_10gR1{22}=q{trace latch};
$latch_name_10gR1{23}=q{FOB s.o list latch};
$latch_name_10gR1{24}=q{FIB s.o chain latch};
$latch_name_10gR1{25}=q{KSFQ};
$latch_name_10gR1{26}=q{X$KSFQP};
$latch_name_10gR1{27}=q{i/o slave adaptor};
$latch_name_10gR1{28}=q{ksfv messages};
$latch_name_10gR1{29}=q{msg queue latch};
$latch_name_10gR1{30}=q{done queue latch};
$latch_name_10gR1{31}=q{session queue latch};
$latch_name_10gR1{32}=q{direct msg latch};
$latch_name_10gR1{33}=q{vecio buf des};
$latch_name_10gR1{34}=q{ksfv subheap};
$latch_name_10gR1{35}=q{resmgr group change latch};
$latch_name_10gR1{36}=q{channel handle pool latch};
$latch_name_10gR1{37}=q{channel operations parent latch};
$latch_name_10gR1{38}=q{message pool operations parent latch};
$latch_name_10gR1{39}=q{channel anchor};
$latch_name_10gR1{40}=q{dynamic channels};
$latch_name_10gR1{41}=q{ksv instance};
$latch_name_10gR1{42}=q{slave class create};
$latch_name_10gR1{43}=q{slave class};
$latch_name_10gR1{44}=q{msg queue};
$latch_name_10gR1{45}=q{first spare latch};
$latch_name_10gR1{46}=q{second spare latch};
$latch_name_10gR1{47}=q{ksxp tid allocation};
$latch_name_10gR1{48}=q{segmented array pool};
$latch_name_10gR1{49}=q{granule operation};
$latch_name_10gR1{50}=q{KSXR large replies};
$latch_name_10gR1{51}=q{SGA mapping latch};
$latch_name_10gR1{52}=q{active service list};
$latch_name_10gR1{53}=q{database property service latch};
$latch_name_10gR1{54}=q{ges process table freelist};
$latch_name_10gR1{55}=q{ges process parent latch};
$latch_name_10gR1{56}=q{ges process hash list};
$latch_name_10gR1{57}=q{ges resource table freelist};
$latch_name_10gR1{58}=q{ges caches resource lists};
$latch_name_10gR1{59}=q{ges resource hash list};
$latch_name_10gR1{60}=q{ges resource scan list};
$latch_name_10gR1{61}=q{ges s-lock bitvec freelist};
$latch_name_10gR1{62}=q{ges enqueue table freelist};
$latch_name_10gR1{63}=q{ges timeout list};
$latch_name_10gR1{64}=q{ges deadlock list};
$latch_name_10gR1{65}=q{ges statistic table};
$latch_name_10gR1{66}=q{ges synchronous data};
$latch_name_10gR1{67}=q{KJC message pool free list};
$latch_name_10gR1{68}=q{KJC receiver ctx free list};
$latch_name_10gR1{69}=q{KJC snd proxy ctx free list};
$latch_name_10gR1{70}=q{KJC destination ctx free list};
$latch_name_10gR1{71}=q{KJC receiver queue access list};
$latch_name_10gR1{72}=q{KJC snd proxy queue access list};
$latch_name_10gR1{73}=q{KJC global post event buffer};
$latch_name_10gR1{74}=q{KJCT receiver queue access};
$latch_name_10gR1{75}=q{KJCT flow control latch};
$latch_name_10gR1{76}=q{ges domain table};
$latch_name_10gR1{77}=q{ges group table};
$latch_name_10gR1{78}=q{gcs resource hash};
$latch_name_10gR1{79}=q{gcs opaque info freelist};
$latch_name_10gR1{80}=q{gcs resource freelist};
$latch_name_10gR1{81}=q{gcs resource scan list};
$latch_name_10gR1{82}=q{gcs resource validate list};
$latch_name_10gR1{83}=q{gcs domain validate latch};
$latch_name_10gR1{84}=q{gcs shadows freelist};
$latch_name_10gR1{85}=q{gcs commit scn state};
$latch_name_10gR1{86}=q{name-service entry};
$latch_name_10gR1{87}=q{name-service request queue};
$latch_name_10gR1{88}=q{name-service pending queue};
$latch_name_10gR1{89}=q{name-service namespace bucket};
$latch_name_10gR1{90}=q{name-service memory objects};
$latch_name_10gR1{91}=q{name-service namespace objects};
$latch_name_10gR1{92}=q{name-service request};
$latch_name_10gR1{93}=q{ges struct kjmddp};
$latch_name_10gR1{94}=q{gcs partitioned table hash};
$latch_name_10gR1{95}=q{gcs pcm hashed value bucket hash};
$latch_name_10gR1{96}=q{gcs partitioned freelist};
$latch_name_10gR1{97}=q{gcs remaster request queue};
$latch_name_10gR1{98}=q{recovery domain freelist};
$latch_name_10gR1{99}=q{recovery domain hash list};
$latch_name_10gR1{100}=q{KMG MMAN ready and startup request latch};
$latch_name_10gR1{101}=q{KMG resize request state object freelist};
$latch_name_10gR1{102}=q{Memory Management Latch};
$latch_name_10gR1{103}=q{Memory Management Parameter Latch};
$latch_name_10gR1{104}=q{file number translation table};
$latch_name_10gR1{105}=q{mostly latch-free SCN};
$latch_name_10gR1{106}=q{lgwr LWN SCN};
$latch_name_10gR1{107}=q{redo on-disk SCN};
$latch_name_10gR1{108}=q{ping redo on-disk SCN};
$latch_name_10gR1{109}=q{Consistent RBA};
$latch_name_10gR1{110}=q{batching SCNs};
$latch_name_10gR1{111}=q{cache buffers lru chain};
$latch_name_10gR1{112}=q{buffer pool};
$latch_name_10gR1{113}=q{multiple dbwriter suspend};
$latch_name_10gR1{114}=q{active checkpoint queue latch};
$latch_name_10gR1{115}=q{checkpoint queue latch};
$latch_name_10gR1{116}=q{cache buffers chains};
$latch_name_10gR1{117}=q{cache buffer handles};
$latch_name_10gR1{118}=q{multiblock read objects};
$latch_name_10gR1{119}=q{cache protection latch};
$latch_name_10gR1{120}=q{simulator lru latch};
$latch_name_10gR1{121}=q{simulator hash latch};
$latch_name_10gR1{122}=q{sim partition latch};
$latch_name_10gR1{123}=q{state object free list};
$latch_name_10gR1{124}=q{object queue header operation};
$latch_name_10gR1{125}=q{object queue header heap};
$latch_name_10gR1{126}=q{Real time apply boundary};
$latch_name_10gR1{127}=q{LGWR NS Write};
$latch_name_10gR1{128}=q{archive control};
$latch_name_10gR1{129}=q{archive process latch};
$latch_name_10gR1{130}=q{managed standby latch};
$latch_name_10gR1{131}=q{alert log latch};
$latch_name_10gR1{132}=q{Managed Standby Recovery State};
$latch_name_10gR1{133}=q{FAL subheap alocation};
$latch_name_10gR1{134}=q{FAL request queue};
$latch_name_10gR1{135}=q{redo writing};
$latch_name_10gR1{136}=q{redo copy};
$latch_name_10gR1{137}=q{redo allocation};
$latch_name_10gR1{138}=q{OS file lock latch};
$latch_name_10gR1{139}=q{KCL instance latch};
$latch_name_10gR1{140}=q{KCL gc element parent latch};
$latch_name_10gR1{141}=q{loader state object freelist};
$latch_name_10gR1{142}=q{begin backup scn array};
$latch_name_10gR1{143}=q{krbmrosl};
$latch_name_10gR1{144}=q{logminer work area};
$latch_name_10gR1{145}=q{logminer context allocation};
$latch_name_10gR1{146}=q{logical standby cache};
$latch_name_10gR1{147}=q{logical standby view};
$latch_name_10gR1{148}=q{media recovery process out of buffers};
$latch_name_10gR1{149}=q{mapped buffers lru chain};
$latch_name_10gR1{150}=q{Media rcv so alloc latch};
$latch_name_10gR1{151}=q{parallel recoverable recovery};
$latch_name_10gR1{152}=q{block media rcv so alloc latch};
$latch_name_10gR1{153}=q{change tracking state change latch};
$latch_name_10gR1{154}=q{change tracking optimization SCN};
$latch_name_10gR1{155}=q{change tracking consistent SCN};
$latch_name_10gR1{156}=q{reservation so alloc latch};
$latch_name_10gR1{157}=q{Reserved Space Latch};
$latch_name_10gR1{158}=q{flashback FBA barrier};
$latch_name_10gR1{159}=q{flashback SCN barrier};
$latch_name_10gR1{160}=q{hint flashback FBA barrier};
$latch_name_10gR1{161}=q{flashback hint SCN barrier};
$latch_name_10gR1{162}=q{flashback allocation};
$latch_name_10gR1{163}=q{flashback mapping};
$latch_name_10gR1{164}=q{flashback copy};
$latch_name_10gR1{165}=q{flashback sync request};
$latch_name_10gR1{166}=q{dml lock allocation};
$latch_name_10gR1{167}=q{list of block allocation};
$latch_name_10gR1{168}=q{transaction allocation};
$latch_name_10gR1{169}=q{dummy allocation};
$latch_name_10gR1{170}=q{transaction branch allocation};
$latch_name_10gR1{171}=q{commit callback allocation};
$latch_name_10gR1{172}=q{sort extent pool};
$latch_name_10gR1{173}=q{shrink stat allocation latch};
$latch_name_10gR1{174}=q{file cache latch};
$latch_name_10gR1{175}=q{undo global data};
$latch_name_10gR1{176}=q{ktm global data};
$latch_name_10gR1{177}=q{parallel txn reco latch};
$latch_name_10gR1{178}=q{intra txn parallel recovery};
$latch_name_10gR1{179}=q{resumable state object};
$latch_name_10gR1{180}=q{In memory undo latch};
$latch_name_10gR1{181}=q{KTF sga enqueue};
$latch_name_10gR1{182}=q{MQL Tracking Latch};
$latch_name_10gR1{183}=q{sequence cache};
$latch_name_10gR1{184}=q{temp lob duration state obj allocation};
$latch_name_10gR1{185}=q{row cache objects};
$latch_name_10gR1{186}=q{QOL Name Generation Latch};
$latch_name_10gR1{187}=q{dictionary lookup};
$latch_name_10gR1{188}=q{global KZLD latch for mem in SGA};
$latch_name_10gR1{189}=q{cost function};
$latch_name_10gR1{190}=q{user lock};
$latch_name_10gR1{191}=q{Policy Refresh Latch};
$latch_name_10gR1{192}=q{Policy Hash Table Latch};
$latch_name_10gR1{193}=q{OLS label cache};
$latch_name_10gR1{194}=q{instance information};
$latch_name_10gR1{195}=q{policy information};
$latch_name_10gR1{196}=q{global ctx hash table latch};
$latch_name_10gR1{197}=q{global tx hash mapping};
$latch_name_10gR1{198}=q{shared pool};
$latch_name_10gR1{199}=q{library cache};
$latch_name_10gR1{200}=q{library cache lock};
$latch_name_10gR1{201}=q{library cache pin};
$latch_name_10gR1{202}=q{library cache pin allocation};
$latch_name_10gR1{203}=q{library cache lock allocation};
$latch_name_10gR1{204}=q{library cache load lock};
$latch_name_10gR1{205}=q{library cache hash chains};
$latch_name_10gR1{206}=q{Token Manager};
$latch_name_10gR1{207}=q{cas latch};
$latch_name_10gR1{208}=q{rm cas latch};
$latch_name_10gR1{209}=q{resmgr:runnable lists};
$latch_name_10gR1{210}=q{resmgr:actses change state};
$latch_name_10gR1{211}=q{resmgr:actses change group};
$latch_name_10gR1{212}=q{resmgr:session queuing};
$latch_name_10gR1{213}=q{resmgr:actses active list};
$latch_name_10gR1{214}=q{resmgr:free threads list};
$latch_name_10gR1{215}=q{resmgr:schema config};
$latch_name_10gR1{216}=q{resmgr:gang list};
$latch_name_10gR1{217}=q{resmgr:queued list};
$latch_name_10gR1{218}=q{resmgr:running actses count};
$latch_name_10gR1{219}=q{resmgr:vc list latch};
$latch_name_10gR1{220}=q{resmgr:incr/decr stats};
$latch_name_10gR1{221}=q{resmgr:method mem alloc latch};
$latch_name_10gR1{222}=q{resmgr:plan CPU method};
$latch_name_10gR1{223}=q{resmgr:resource group CPU method};
$latch_name_10gR1{224}=q{QMT};
$latch_name_10gR1{225}=q{Streams Generic};
$latch_name_10gR1{226}=q{Shared B-Tree};
$latch_name_10gR1{227}=q{Memory Queue};
$latch_name_10gR1{228}=q{Memory Queue Subscriber};
$latch_name_10gR1{229}=q{peplm};
$latch_name_10gR1{230}=q{dispatcher configuration};
$latch_name_10gR1{231}=q{session timer};
$latch_name_10gR1{232}=q{parameter list};
$latch_name_10gR1{233}=q{presentation list};
$latch_name_10gR1{234}=q{address list};
$latch_name_10gR1{235}=q{end-point list};
$latch_name_10gR1{236}=q{shared server info};
$latch_name_10gR1{237}=q{dispatcher info};
$latch_name_10gR1{238}=q{virtual circuit buffers};
$latch_name_10gR1{239}=q{virtual circuit queues};
$latch_name_10gR1{240}=q{virtual circuits};
$latch_name_10gR1{241}=q{kmcptab latch};
$latch_name_10gR1{242}=q{kmcpvec latch};
$latch_name_10gR1{243}=q{JOX SGA heap latch};
$latch_name_10gR1{244}=q{job_queue_processes parameter latch};
$latch_name_10gR1{245}=q{job workq parent latch};
$latch_name_10gR1{246}=q{job_queue_processes free list latch};
$latch_name_10gR1{247}=q{child cursor hash table};
$latch_name_10gR1{248}=q{cursor bind value capture};
$latch_name_10gR1{249}=q{query server process};
$latch_name_10gR1{250}=q{query server freelists};
$latch_name_10gR1{251}=q{error message lists};
$latch_name_10gR1{252}=q{process queue};
$latch_name_10gR1{253}=q{process queue reference};
$latch_name_10gR1{254}=q{parallel query stats};
$latch_name_10gR1{255}=q{business card};
$latch_name_10gR1{256}=q{parallel query alloc buffer};
$latch_name_10gR1{257}=q{hash table modification latch};
$latch_name_10gR1{258}=q{hash table column usage latch};
$latch_name_10gR1{259}=q{constraint object allocation};
$latch_name_10gR1{260}=q{device information};
$latch_name_10gR1{261}=q{temporary table state object allocation};
$latch_name_10gR1{262}=q{internal temp table object number allocation latc};
$latch_name_10gR1{263}=q{SQL memory manager latch};
$latch_name_10gR1{264}=q{SQL memory manager workarea list latch};
$latch_name_10gR1{265}=q{compile environment latch};
$latch_name_10gR1{266}=q{kupp process latch};
$latch_name_10gR1{267}=q{pass worker exception to master};
$latch_name_10gR1{268}=q{datapump job fixed tables latch};
$latch_name_10gR1{269}=q{datapump attach fixed tables latch};
$latch_name_10gR1{270}=q{ncodef allocation latch};
$latch_name_10gR1{271}=q{NLS data objects};
$latch_name_10gR1{272}=q{spilled notification count};
$latch_name_10gR1{273}=q{numer of job queues for server notfn};
$latch_name_10gR1{274}=q{message enqueue sync latch};
$latch_name_10gR1{275}=q{image handles of buffered messages latch};
$latch_name_10gR1{276}=q{kwqi:kchunk latch};
$latch_name_10gR1{277}=q{kwqit: protect wakeup time};
$latch_name_10gR1{278}=q{KWQP Prop Status};
$latch_name_10gR1{279}=q{AQ Propagation Scheduling Proc Table};
$latch_name_10gR1{280}=q{AQ Propagation Scheduling System Load};
$latch_name_10gR1{281}=q{rules engine statistics};
$latch_name_10gR1{282}=q{enqueue sob latch};
$latch_name_10gR1{283}=q{kwqbsgn:msghdr};
$latch_name_10gR1{284}=q{kwqbsn:qxl};
$latch_name_10gR1{285}=q{kwqbsn:qsga};
$latch_name_10gR1{286}=q{kwqbcco:cco};
$latch_name_10gR1{287}=q{bufq statistics};
$latch_name_10gR1{288}=q{spilled messages latch};
$latch_name_10gR1{289}=q{queue sender's info. latch};
$latch_name_10gR1{290}=q{qmn task queue latch};
$latch_name_10gR1{291}=q{qmn state object latch};
$latch_name_10gR1{292}=q{KWQMN job instance list latch};
$latch_name_10gR1{293}=q{KWQMN job cache list latch};
$latch_name_10gR1{294}=q{process};
$latch_name_10gR1{295}=q{TXN SGA};
$latch_name_10gR1{296}=q{fixed table rows for x$hs_session};
$latch_name_10gR1{297}=q{qm_init_sga};
$latch_name_10gR1{298}=q{XDB unused session pool};
$latch_name_10gR1{299}=q{XDB used session pool};
$latch_name_10gR1{300}=q{XDB Config};
$latch_name_10gR1{301}=q{DMON Process Context Latch};
$latch_name_10gR1{302}=q{DMON Work Queues Latch};
$latch_name_10gR1{303}=q{RSM process latch};
$latch_name_10gR1{304}=q{RSM SQL latch};
$latch_name_10gR1{305}=q{Request id generation latch};
$latch_name_10gR1{306}=q{xscalc freelist};
$latch_name_10gR1{307}=q{xssinfo freelist};
$latch_name_10gR1{308}=q{AW SGA latch};
$latch_name_10gR1{309}=q{ASM allocation};
$latch_name_10gR1{310}=q{KFA SGA latch};
$latch_name_10gR1{311}=q{buffer pin latch};
$latch_name_10gR1{312}=q{KFC SGA latch};
$latch_name_10gR1{313}=q{KFC LRU latch};
$latch_name_10gR1{314}=q{KFC Hash Latch};
$latch_name_10gR1{315}=q{KFC FX Hash Latch};
$latch_name_10gR1{316}=q{OSM map headers};
$latch_name_10gR1{317}=q{OSM map operation freelist};
$latch_name_10gR1{318}=q{OSM map operation hash table};
$latch_name_10gR1{319}=q{OSM map load waiting list};
$latch_name_10gR1{320}=q{KFK SGA context latch};
$latch_name_10gR1{321}=q{KFM allocation};
$latch_name_10gR1{322}=q{KFMD SGA};
$latch_name_10gR1{323}=q{ASM network background latch};
$latch_name_10gR1{324}=q{ASM db client latch};
$latch_name_10gR1{325}=q{ASM file allocation latch};
$latch_name_10gR1{326}=q{ASM file locked extent latch};
$latch_name_10gR1{327}=q{KFR redo allocation latch};
$latch_name_10gR1{328}=q{OSM rollback operations};
$latch_name_10gR1{329}=q{KFCL LE Freelist};
$latch_name_10gR1{330}=q{KFCL Instance Latch};
$latch_name_10gR1{331}=q{KFCL BX Freelist};
$latch_name_10gR1{332}=q{server alert latch};
$latch_name_10gR1{333}=q{generalized trace enabling latch};
$latch_name_10gR1{334}=q{statistics aggregation};
$latch_name_10gR1{335}=q{SWRF Alerted Metric Element list};
$latch_name_10gR1{336}=q{threshold alerts latch};
$latch_name_10gR1{337}=q{alert memory latch};
$latch_name_10gR1{338}=q{JS broadcast add buf latch};
$latch_name_10gR1{339}=q{JS broadcast drop buf latch};
$latch_name_10gR1{340}=q{JS broadcast kill buf latch};
$latch_name_10gR1{341}=q{JS broadcast load blnc latch};
$latch_name_10gR1{342}=q{JS broadcast autostart latch};
$latch_name_10gR1{343}=q{JS mem alloc latch};
$latch_name_10gR1{344}=q{JS slv state obj latch};
$latch_name_10gR1{345}=q{JS queue state obj latch};
$latch_name_10gR1{346}=q{JS queue access latch};
$latch_name_10gR1{347}=q{PL/SQL warning settings};

# 10g Release2 latch number to latch name mapping
my %latch_name_10gR2;
$latch_name_10gR2{0}="event range base latch";                                  
$latch_name_10gR2{1}="post/wait queue";                                         
$latch_name_10gR2{2}="hot latch diags";                                         
$latch_name_10gR2{3}="process allocation";                                      
$latch_name_10gR2{4}="session allocation";                                      
$latch_name_10gR2{5}="session switching";                                       
$latch_name_10gR2{6}="process group creation";                                  
$latch_name_10gR2{7}="session idle bit";                                        
$latch_name_10gR2{8}="client/application info";                                 
$latch_name_10gR2{9}="longop free list parent";                                 
$latch_name_10gR2{10}="ksuosstats global area";                                 
$latch_name_10gR2{11}="ksupkttest latch";                                       
$latch_name_10gR2{12}="cached attr list";                                       
$latch_name_10gR2{13}="object stats modification";                              
$latch_name_10gR2{14}="Testing";                                                
$latch_name_10gR2{15}="parameter table allocation management";                  
$latch_name_10gR2{16}="event group latch";                                      
$latch_name_10gR2{17}="messages";                                               
$latch_name_10gR2{18}="enqueues";                                               
$latch_name_10gR2{19}="enqueue hash chains";                                    
$latch_name_10gR2{20}="instance enqueue";                                       
$latch_name_10gR2{21}="trace latch";                                            
$latch_name_10gR2{22}="FOB s.o list latch";                                     
$latch_name_10gR2{23}="FIB s.o chain latch";                                    
$latch_name_10gR2{24}="SGA IO buffer pool latch";                               
$latch_name_10gR2{25}="KSFQ";                                                   
$latch_name_10gR2{26}=q{X$KSFQP};                                                
$latch_name_10gR2{27}="i/o slave adaptor";                                      
$latch_name_10gR2{28}="ksfv messages";                                          
$latch_name_10gR2{29}="msg queue latch";                                        
$latch_name_10gR2{30}="done queue latch";                                       
$latch_name_10gR2{31}="session queue latch";                                    
$latch_name_10gR2{32}="direct msg latch";                                       
$latch_name_10gR2{33}="vecio buf des";                                          
$latch_name_10gR2{34}="ksfv subheap";                                           
$latch_name_10gR2{35}="resmgr group change latch";                              
$latch_name_10gR2{36}="channel handle pool latch";                              
$latch_name_10gR2{37}="channel operations parent latch";                        
$latch_name_10gR2{38}="message pool operations parent latch";                   
$latch_name_10gR2{39}="channel anchor";                                         
$latch_name_10gR2{40}="dynamic channels";                                       
$latch_name_10gR2{41}="ksv instance";                                           
$latch_name_10gR2{42}="slave class create";                                     
$latch_name_10gR2{43}="slave class";                                            
$latch_name_10gR2{44}="msg queue";                                              
$latch_name_10gR2{45}="first spare latch";                                      
$latch_name_10gR2{46}="second spare latch";                                     
$latch_name_10gR2{47}="ksxp tid allocation";                                    
$latch_name_10gR2{48}="segmented array pool";                                   
$latch_name_10gR2{49}="granule operation";                                      
$latch_name_10gR2{50}="KSXR large replies";                                     
$latch_name_10gR2{51}="SGA mapping latch";                                      
$latch_name_10gR2{52}="active service list";                                    
$latch_name_10gR2{53}="database property service latch";                        
$latch_name_10gR2{54}="OS process allocation";                                  
$latch_name_10gR2{55}="OS process";                                             
$latch_name_10gR2{56}="OS process: request allocation";                         
$latch_name_10gR2{57}="ksir sga latch";                                         
$latch_name_10gR2{58}="queued dump request";                                    
$latch_name_10gR2{59}="global hanganlyze operation";                            
$latch_name_10gR2{60}="ges process table freelist";                             
$latch_name_10gR2{61}="ges process parent latch";                               
$latch_name_10gR2{62}="ges process hash list";                                  
$latch_name_10gR2{63}="ges resource table freelist";                            
$latch_name_10gR2{64}="ges caches resource lists";                              
$latch_name_10gR2{65}="ges resource hash list";                                 
$latch_name_10gR2{66}="ges resource scan list";                                 
$latch_name_10gR2{67}="ges s-lock bitvec freelist";                             
$latch_name_10gR2{68}="ges enqueue table freelist";                             
$latch_name_10gR2{69}="ges timeout list";                                       
$latch_name_10gR2{70}="ges deadlock list";                                      
$latch_name_10gR2{71}="ges statistic table";                                    
$latch_name_10gR2{72}="ges synchronous data";                                   
$latch_name_10gR2{73}="KJC message pool free list";                             
$latch_name_10gR2{74}="KJC receiver ctx free list";                             
$latch_name_10gR2{75}="KJC snd proxy ctx free list";                            
$latch_name_10gR2{76}="KJC destination ctx free list";                          
$latch_name_10gR2{77}="KJC receiver queue access list";                         
$latch_name_10gR2{78}="KJC snd proxy queue access list";                        
$latch_name_10gR2{79}="KJC global post event buffer";                           
$latch_name_10gR2{80}="KJC global resend message queue";                        
$latch_name_10gR2{81}="KJCT receiver queue access";                             
$latch_name_10gR2{82}="KJCT flow control latch";                                
$latch_name_10gR2{83}="ges domain table";                                       
$latch_name_10gR2{84}="ges group table";                                        
$latch_name_10gR2{85}="gcs resource hash";                                      
$latch_name_10gR2{86}="gcs opaque info freelist";                               
$latch_name_10gR2{87}="gcs resource freelist";                                  
$latch_name_10gR2{88}="gcs resource scan list";                                 
$latch_name_10gR2{89}="gcs resource validate list";                             
$latch_name_10gR2{90}="gcs domain validate latch";                              
$latch_name_10gR2{91}="gcs shadows freelist";                                   
$latch_name_10gR2{92}="gcs commit scn state";                                   
$latch_name_10gR2{93}="gcs drop object freelist";                               
$latch_name_10gR2{94}="name-service entry";                                     
$latch_name_10gR2{95}="name-service request queue";                             
$latch_name_10gR2{96}="name-service pending queue";                             
$latch_name_10gR2{97}="name-service namespace bucket";                          
$latch_name_10gR2{98}="name-service memory objects";                            
$latch_name_10gR2{99}="name-service namespace objects";                         
$latch_name_10gR2{100}="name-service request";                                  
$latch_name_10gR2{101}="gcs remastering latch";                                 
$latch_name_10gR2{102}="gcs partitioned table hash";                            
$latch_name_10gR2{103}="gcs pcm hashed value bucket hash";                      
$latch_name_10gR2{104}="gcs remaster request queue";                            
$latch_name_10gR2{105}="recovery domain freelist";                              
$latch_name_10gR2{106}="recovery domain hash list";                             
$latch_name_10gR2{107}="KMG MMAN ready and startup request latch";              
$latch_name_10gR2{108}="KMG resize request state object freelist";              
$latch_name_10gR2{109}="Memory Management Latch";                               
$latch_name_10gR2{110}="Memory Management Parameter Latch";                     
$latch_name_10gR2{111}="file number translation table";                         
$latch_name_10gR2{112}="mostly latch-free SCN";                                 
$latch_name_10gR2{113}="lgwr LWN SCN";                                          
$latch_name_10gR2{114}="redo on-disk SCN";                                      
$latch_name_10gR2{115}="ping redo on-disk SCN";                                 
$latch_name_10gR2{116}="Consistent RBA";                                        
$latch_name_10gR2{117}="cache buffers lru chain";                               
$latch_name_10gR2{118}="buffer pool";                                           
$latch_name_10gR2{119}="multiple dbwriter suspend";                             
$latch_name_10gR2{120}="active checkpoint queue latch";                         
$latch_name_10gR2{121}="checkpoint queue latch";                                
$latch_name_10gR2{122}="cache buffers chains";                                  
$latch_name_10gR2{123}="cache buffer handles";                                  
$latch_name_10gR2{124}="multiblock read objects";                               
$latch_name_10gR2{125}="cache protection latch";                                
$latch_name_10gR2{126}="cache table scan latch";                                
$latch_name_10gR2{127}="simulator lru latch";                                   
$latch_name_10gR2{128}="simulator hash latch";                                  
$latch_name_10gR2{129}="sim partition latch";                                   
$latch_name_10gR2{130}="state object free list";                                
$latch_name_10gR2{131}="object queue header operation";                         
$latch_name_10gR2{132}="object queue header heap";                              
$latch_name_10gR2{133}="Real time apply boundary";                              
$latch_name_10gR2{134}="LGWR NS Write";                                         
$latch_name_10gR2{135}="archive control";                                       
$latch_name_10gR2{136}="archive process latch";                                 
$latch_name_10gR2{137}="managed standby latch";                                 
$latch_name_10gR2{138}="alert log latch";                                       
$latch_name_10gR2{139}="SGA kcrrgap latch";                                     
$latch_name_10gR2{140}="SGA kcrrpinfo latch";                                   
$latch_name_10gR2{141}="SGA kcrrssncpl latch";                                  
$latch_name_10gR2{142}="SGA kcrrlatmscnl latch";                                
$latch_name_10gR2{143}="Managed Standby Recovery State";                        
$latch_name_10gR2{144}="FAL subheap alocation";                                 
$latch_name_10gR2{145}="FAL request queue";                                     
$latch_name_10gR2{146}="redo writing";                                          
$latch_name_10gR2{147}="redo copy";                                             
$latch_name_10gR2{148}="redo allocation";                                       
$latch_name_10gR2{149}="OS file lock latch";                                    
$latch_name_10gR2{150}="KCL gc element parent latch";                           
$latch_name_10gR2{151}="loader state object freelist";                          
$latch_name_10gR2{152}="begin backup scn array";                                
$latch_name_10gR2{153}="krbmrosl";                                              
$latch_name_10gR2{154}="logminer work area";                                    
$latch_name_10gR2{155}="logminer context allocation";                           
$latch_name_10gR2{156}="logical standby cache";                                 
$latch_name_10gR2{157}="logical standby view";                                  
$latch_name_10gR2{158}="media recovery process out of buffers";                 
$latch_name_10gR2{159}="mapped buffers lru chain";                              
$latch_name_10gR2{160}="Media rcv so alloc latch";                              
$latch_name_10gR2{161}="parallel recoverable recovery";                         
$latch_name_10gR2{162}="block media rcv so alloc latch";                        
$latch_name_10gR2{163}="change tracking state change latch";                    
$latch_name_10gR2{164}="change tracking optimization SCN";                      
$latch_name_10gR2{165}="change tracking consistent SCN";                        
$latch_name_10gR2{166}="reservation so alloc latch";                            
$latch_name_10gR2{167}="Reserved Space Latch";                                  
$latch_name_10gR2{168}="flashback FBA barrier";                                 
$latch_name_10gR2{169}="flashback SCN barrier";                                 
$latch_name_10gR2{170}="hint flashback FBA barrier";                            
$latch_name_10gR2{171}="flashback hint SCN barrier";                            
$latch_name_10gR2{172}="flashback allocation";                                  
$latch_name_10gR2{173}="flashback mapping";                                     
$latch_name_10gR2{174}="flashback copy";                                        
$latch_name_10gR2{175}="flashback sync request";                                
$latch_name_10gR2{176}="Transportable DB Context Latch";                        
$latch_name_10gR2{177}="dml lock allocation";                                   
$latch_name_10gR2{178}="list of block allocation";                              
$latch_name_10gR2{179}="transaction allocation";                                
$latch_name_10gR2{180}="dummy allocation";                                      
$latch_name_10gR2{181}="transaction branch allocation";                         
$latch_name_10gR2{182}="commit callback allocation";                            
$latch_name_10gR2{183}="sort extent pool";                                      
$latch_name_10gR2{184}="shrink stat allocation latch";                          
$latch_name_10gR2{185}="file cache latch";                                      
$latch_name_10gR2{186}="undo global data";                                      
$latch_name_10gR2{187}="ktm global data";                                       
$latch_name_10gR2{188}="parallel txn reco latch";                               
$latch_name_10gR2{189}="intra txn parallel recovery";                           
$latch_name_10gR2{190}="Undo Hint Latch";                                       
$latch_name_10gR2{191}="resumable state object";                                
$latch_name_10gR2{192}="In memory undo latch";                                  
$latch_name_10gR2{193}="KTF sga latch";                                         
$latch_name_10gR2{194}="MQL Tracking Latch";                                    
$latch_name_10gR2{195}="Change Notification Hash table latch";                  
$latch_name_10gR2{196}="Change Notification Latch";                             
$latch_name_10gR2{197}="sequence cache";                                        
$latch_name_10gR2{198}="temp lob duration state obj allocation";                
$latch_name_10gR2{199}="row cache objects";                                     
$latch_name_10gR2{200}="QOL Name Generation Latch";                             
$latch_name_10gR2{201}="dictionary lookup";                                     
$latch_name_10gR2{202}="kks stats";                                             
$latch_name_10gR2{203}="global KZLD latch for mem in SGA";                      
$latch_name_10gR2{204}="cost function";                                         
$latch_name_10gR2{205}="user lock";                                             
$latch_name_10gR2{206}="Policy Refresh Latch";                                  
$latch_name_10gR2{207}="Policy Hash Table Latch";                               
$latch_name_10gR2{208}="OLS label cache";                                       
$latch_name_10gR2{209}="instance information";                                  
$latch_name_10gR2{210}="policy information";                                    
$latch_name_10gR2{211}="global ctx hash table latch";                           
$latch_name_10gR2{212}="global tx hash mapping";                                
$latch_name_10gR2{213}="shared pool";                                           
$latch_name_10gR2{214}="library cache";                                         
$latch_name_10gR2{215}="library cache lock";                                    
$latch_name_10gR2{216}="library cache pin";                                     
$latch_name_10gR2{217}="library cache pin allocation";                          
$latch_name_10gR2{218}="library cache lock allocation";                         
$latch_name_10gR2{219}="library cache load lock";                               
$latch_name_10gR2{220}="library cache hash chains";                             
$latch_name_10gR2{221}="Token Manager";                                         
$latch_name_10gR2{222}="cas latch";                                             
$latch_name_10gR2{223}="rm cas latch";                                          
$latch_name_10gR2{224}="resmgr:runnable lists";                                 
$latch_name_10gR2{225}="resmgr:actses change state";                            
$latch_name_10gR2{226}="resmgr:actses change group";                            
$latch_name_10gR2{227}="resmgr:session queuing";                                
$latch_name_10gR2{228}="resmgr:actses active list";                             
$latch_name_10gR2{229}="resmgr:free threads list";                              
$latch_name_10gR2{230}="resmgr:schema config";                                  
$latch_name_10gR2{231}="resmgr:gang list";                                      
$latch_name_10gR2{232}="resmgr:queued list";                                    
$latch_name_10gR2{233}="resmgr:running actses count";                           
$latch_name_10gR2{234}="resmgr:vc list latch";                                  
$latch_name_10gR2{235}="resmgr:incr/decr stats";                                
$latch_name_10gR2{236}="resmgr:method mem alloc latch";                         
$latch_name_10gR2{237}="resmgr:plan CPU method";                                
$latch_name_10gR2{238}="resmgr:resource group CPU method";                      
$latch_name_10gR2{239}="QMT";                                                   
$latch_name_10gR2{240}="shared pool simulator";                                 
$latch_name_10gR2{241}="shared pool sim alloc";                                 
$latch_name_10gR2{242}="Streams Generic";                                       
$latch_name_10gR2{243}="Shared B-Tree";                                         
$latch_name_10gR2{244}="Memory Queue";                                          
$latch_name_10gR2{245}="Memory Queue Subscriber";                               
$latch_name_10gR2{246}="Memory Queue Message Subscriber #1";                    
$latch_name_10gR2{247}="Memory Queue Message Subscriber #2";                    
$latch_name_10gR2{248}="Memory Queue Message Subscriber #3";                    
$latch_name_10gR2{249}="Memory Queue Message Subscriber #4";                    
$latch_name_10gR2{250}="peplm";                                                 
$latch_name_10gR2{251}="Mutex";                                                 
$latch_name_10gR2{252}="Mutex Stats";                                           
$latch_name_10gR2{253}="pebof_rrv";                                             
$latch_name_10gR2{254}="shared server configuration";                           
$latch_name_10gR2{255}="session timer";                                         
$latch_name_10gR2{256}="parameter list";                                        
$latch_name_10gR2{257}="presentation list";                                     
$latch_name_10gR2{258}="address list";                                          
$latch_name_10gR2{259}="end-point list";                                        
$latch_name_10gR2{260}="shared server info";                                    
$latch_name_10gR2{261}="dispatcher info";                                       
$latch_name_10gR2{262}="virtual circuit buffers";                               
$latch_name_10gR2{263}="virtual circuit queues";                                
$latch_name_10gR2{264}="virtual circuits";                                      
$latch_name_10gR2{265}="kmcptab latch";                                         
$latch_name_10gR2{266}="kmcpvec latch";                                         
$latch_name_10gR2{267}="JOX SGA heap latch";                                    
$latch_name_10gR2{268}="job_queue_processes parameter latch";                   
$latch_name_10gR2{269}="job workq parent latch";                                
$latch_name_10gR2{270}="job_queue_processes free list latch";                   
$latch_name_10gR2{271}="query server process";                                  
$latch_name_10gR2{272}="query server freelists";                                
$latch_name_10gR2{273}="error message lists";                                   
$latch_name_10gR2{274}="process queue";                                         
$latch_name_10gR2{275}="process queue reference";                               
$latch_name_10gR2{276}="parallel query stats";                                  
$latch_name_10gR2{277}="business card";                                         
$latch_name_10gR2{278}="parallel query alloc buffer";                           
$latch_name_10gR2{279}="hash table modification latch";                         
$latch_name_10gR2{280}="hash table column usage latch";                         
$latch_name_10gR2{281}="constraint object allocation";                          
$latch_name_10gR2{282}="device information";                                    
$latch_name_10gR2{283}="temporary table state object allocation";               
$latch_name_10gR2{284}="internal temp table object number allocation latc";     
$latch_name_10gR2{285}="SQL memory manager latch";                              
$latch_name_10gR2{286}="SQL memory manager workarea list latch";                
$latch_name_10gR2{287}="compile environment latch";                             
$latch_name_10gR2{288}="Bloom filter list latch";                               
$latch_name_10gR2{289}="Bloom Filter SGA latch";                                
$latch_name_10gR2{290}="bug fix control action latch";                          
$latch_name_10gR2{291}="kupp process latch";                                    
$latch_name_10gR2{292}="pass worker exception to master";                       
$latch_name_10gR2{293}="datapump job fixed tables latch";                       
$latch_name_10gR2{294}="datapump attach fixed tables latch";                    
$latch_name_10gR2{295}="process";                                               
$latch_name_10gR2{296}="TXN SGA";                                               
$latch_name_10gR2{297}="STREAMS LCR";                                           
$latch_name_10gR2{298}="STREAMS Pool Advisor";                                  
$latch_name_10gR2{299}="ncodef allocation latch";                               
$latch_name_10gR2{300}="NLS data objects";                                      
$latch_name_10gR2{301}="kpon sga structure";                                    
$latch_name_10gR2{302}="numer of job queues for server notfn";                  
$latch_name_10gR2{303}=q{reg$ timeout service time};                             
$latch_name_10gR2{304}="KPON ksr channel latch";                                
$latch_name_10gR2{305}="session state list latch";                              
$latch_name_10gR2{306}="message enqueue sync latch";                            
$latch_name_10gR2{307}="image handles of buffered messages latch";              
$latch_name_10gR2{308}="kwqi:kchunk latch";                                     
$latch_name_10gR2{309}="KWQP Prop Status";                                      
$latch_name_10gR2{310}="AQ Propagation Scheduling Proc Table";                  
$latch_name_10gR2{311}="AQ Propagation Scheduling System Load";                 
$latch_name_10gR2{312}="job queue sob latch";                                   
$latch_name_10gR2{313}="rules engine aggregate statistics";                     
$latch_name_10gR2{314}="rules engine rule set statistics";                      
$latch_name_10gR2{315}="rules engine rule statistics";                          
$latch_name_10gR2{316}="rules engine evaluation context statistics";            
$latch_name_10gR2{317}="enqueue sob latch";                                     
$latch_name_10gR2{318}="kwqbsgn:msghdr";                                        
$latch_name_10gR2{319}="kwqbsn:qxl";                                            
$latch_name_10gR2{320}="kwqbsn:qsga";                                           
$latch_name_10gR2{321}="kwqbcco:cco";                                           
$latch_name_10gR2{322}="bufq statistics";                                       
$latch_name_10gR2{323}="spilled messages latch";                                
$latch_name_10gR2{324}="queue sender's info. latch";                            
$latch_name_10gR2{325}="bq:time manger info latch";                             
$latch_name_10gR2{326}="qmn task queue latch";                                  
$latch_name_10gR2{327}="qmn state object latch";                                
$latch_name_10gR2{328}="KWQMN job cache list latch";                            
$latch_name_10gR2{329}="KWQMN to-be-Stopped Buffer list Latch";                 
$latch_name_10gR2{330}=q{fixed table rows for x$hs_session};                     
$latch_name_10gR2{331}="qm_init_sga";                                           
$latch_name_10gR2{332}="XDB unused session pool";                               
$latch_name_10gR2{333}="XDB used session pool";                                 
$latch_name_10gR2{334}="XDB Config";                                            
$latch_name_10gR2{335}="DMON Process Context Latch";                            
$latch_name_10gR2{336}="DMON Work Queues Latch";                                
$latch_name_10gR2{337}="RSM process latch";                                     
$latch_name_10gR2{338}="RSM SQL latch";                                         
$latch_name_10gR2{339}="Request id generation latch";                           
$latch_name_10gR2{340}="Fast-Start Failover State Latch";                       
$latch_name_10gR2{341}="xscalc freelist";                                       
$latch_name_10gR2{342}="xssinfo freelist";                                      
$latch_name_10gR2{343}="AW SGA latch";                                          
$latch_name_10gR2{344}="ASM allocation";                                        
$latch_name_10gR2{345}="KFA SGA latch";                                         
$latch_name_10gR2{346}="buffer pin latch";                                      
$latch_name_10gR2{347}="KFC SGA latch";                                         
$latch_name_10gR2{348}="KFC LRU latch";                                         
$latch_name_10gR2{349}="KFC Hash Latch";                                        
$latch_name_10gR2{350}="KFC FX Hash Latch";                                     
$latch_name_10gR2{351}="ASM map headers";                                       
$latch_name_10gR2{352}="ASM map operation freelist";                            
$latch_name_10gR2{353}="ASM map operation hash table";                          
$latch_name_10gR2{354}="ASM map load waiting list";                             
$latch_name_10gR2{355}="KFK SGA context latch";                                 
$latch_name_10gR2{356}="KFM allocation";                                        
$latch_name_10gR2{357}="KFMD SGA";                                              
$latch_name_10gR2{358}="ASM network background latch";                          
$latch_name_10gR2{359}="ASM db client latch";                                   
$latch_name_10gR2{360}="ASM file allocation latch";                             
$latch_name_10gR2{361}="ASM file locked extent latch";                          
$latch_name_10gR2{362}="KFR redo allocation latch";                             
$latch_name_10gR2{363}="ASM rollback operations";                               
$latch_name_10gR2{364}="KFCL LE Freelist";                                      
$latch_name_10gR2{365}="KFCL Instance Latch";                                   
$latch_name_10gR2{366}="KFCL BX Freelist";                                      
$latch_name_10gR2{367}="server alert latch";                                    
$latch_name_10gR2{368}="generalized trace enabling latch";                      
$latch_name_10gR2{369}="statistics aggregation";                                
$latch_name_10gR2{370}="AWR Alerted Metric Element list";                       
$latch_name_10gR2{371}="threshold alerts latch";                                
$latch_name_10gR2{372}="alert memory latch";                                    
$latch_name_10gR2{373}="JS broadcast add buf latch";                            
$latch_name_10gR2{374}="JS broadcast drop buf latch";                           
$latch_name_10gR2{375}="JS broadcast kill buf latch";                           
$latch_name_10gR2{376}="JS event notify broadcast latch";                       
$latch_name_10gR2{377}="JS broadcast load blnc latch";                          
$latch_name_10gR2{378}="JS broadcast autostart latch";                          
$latch_name_10gR2{379}="JS mem alloc latch";                                    
$latch_name_10gR2{380}="JS slv state obj latch";                                
$latch_name_10gR2{381}="JS queue state obj latch";                              
$latch_name_10gR2{382}="JS queue access latch";                                 
$latch_name_10gR2{383}="JS Sh mem access";                                      
$latch_name_10gR2{384}="PL/SQL warning settings";                               

# 11g Release1 latch number to latch name mapping
my %latch_name_11gR1;
$latch_name_11gR1{0}=q{PC and Classifier lists for WLM};                        
$latch_name_11gR1{1}=q{event range base latch};                                 
$latch_name_11gR1{2}=q{post/wait queue};                                        
$latch_name_11gR1{3}=q{hot latch diags};                                        
$latch_name_11gR1{4}=q{test excl. non-parent l0};                               
$latch_name_11gR1{5}=q{test excl. parent l0};                                   
$latch_name_11gR1{6}=q{test excl. parent2 l0};                                  
$latch_name_11gR1{7}=q{test shared non-parent l0};                              
$latch_name_11gR1{8}=q{test excl. non-parent lmax};                             
$latch_name_11gR1{9}=q{process allocation};                                     
$latch_name_11gR1{10}=q{session allocation};                                    
$latch_name_11gR1{11}=q{session switching};                                     
$latch_name_11gR1{12}=q{process group creation};                                
$latch_name_11gR1{13}=q{session idle bit};                                      
$latch_name_11gR1{14}=q{client/application info};                               
$latch_name_11gR1{15}=q{longop free list parent};                               
$latch_name_11gR1{16}=q{ksuosstats global area};                                
$latch_name_11gR1{17}=q{ksupkttest latch};                                      
$latch_name_11gR1{18}=q{cached attr list};                                      
$latch_name_11gR1{19}=q{ksim membership request latch};                         
$latch_name_11gR1{20}=q{object stats modification};                             
$latch_name_11gR1{21}=q{kss move lock};                                         
$latch_name_11gR1{22}=q{parameter table management};                            
$latch_name_11gR1{23}=q{ksbxic instance latch};                                 
$latch_name_11gR1{24}=q{kse signature};                                         
$latch_name_11gR1{25}=q{messages};                                              
$latch_name_11gR1{26}=q{enqueues};                                              
$latch_name_11gR1{27}=q{enqueue hash chains};                                   
$latch_name_11gR1{28}=q{instance enqueue};                                      
$latch_name_11gR1{29}=q{trace latch};                                           
$latch_name_11gR1{30}=q{FOB s.o list latch};                                    
$latch_name_11gR1{31}=q{FIB s.o chain latch};                                   
$latch_name_11gR1{32}=q{SGA IO buffer pool latch};                              
$latch_name_11gR1{33}=q{File IO Stats segmented array latch};                   
$latch_name_11gR1{34}=q{KSFQ};                                                  
$latch_name_11gR1{35}=q{X$KSFQP};                                               
$latch_name_11gR1{36}=q{i/o slave adaptor};                                     
$latch_name_11gR1{37}=q{ksfv messages};                                         
$latch_name_11gR1{38}=q{msg queue latch};                                       
$latch_name_11gR1{39}=q{done queue latch};                                      
$latch_name_11gR1{40}=q{session queue latch};                                   
$latch_name_11gR1{41}=q{direct msg latch};                                      
$latch_name_11gR1{42}=q{vecio buf des};                                         
$latch_name_11gR1{43}=q{ksfv subheap};                                          
$latch_name_11gR1{44}=q{resmgr:free threads list};                              
$latch_name_11gR1{45}=q{resmgr group change latch};                             
$latch_name_11gR1{46}=q{channel handle pool latch};                             
$latch_name_11gR1{47}=q{channel operations parent latch};                       
$latch_name_11gR1{48}=q{message pool operations parent latch};                  
$latch_name_11gR1{49}=q{channel anchor};                                        
$latch_name_11gR1{50}=q{dynamic channels};                                      
$latch_name_11gR1{51}=q{ksv instance latch};                                    
$latch_name_11gR1{52}=q{ksv class latch};                                       
$latch_name_11gR1{53}=q{ksv msg queue latch};                                   
$latch_name_11gR1{54}=q{ksv allocation latch};                                  
$latch_name_11gR1{55}=q{ksv remote inst ops};                                   
$latch_name_11gR1{56}=q{first spare latch};                                     
$latch_name_11gR1{57}=q{second spare latch};                                    
$latch_name_11gR1{58}=q{third spare latch};                                     
$latch_name_11gR1{59}=q{fourth spare latch};                                    
$latch_name_11gR1{60}=q{fifth spare latch};                                     
$latch_name_11gR1{61}=q{ksxp shared latch};                                     
$latch_name_11gR1{62}=q{IPC stats buffer allocation latch};                     
$latch_name_11gR1{63}=q{segmented array pool};                                  
$latch_name_11gR1{64}=q{granule operation};                                     
$latch_name_11gR1{65}=q{KSXR large replies};                                    
$latch_name_11gR1{66}=q{SGA mapping latch};                                     
$latch_name_11gR1{67}=q{active service list};                                   
$latch_name_11gR1{68}=q{database property service latch};                       
$latch_name_11gR1{69}=q{OS process allocation};                                 
$latch_name_11gR1{70}=q{OS process};                                            
$latch_name_11gR1{71}=q{OS process: request allocation};                        
$latch_name_11gR1{72}=q{ksir sga latch};                                        
$latch_name_11gR1{73}=q{kspoltest latch};                                       
$latch_name_11gR1{74}=q{ksz_so allocation latch};                               
$latch_name_11gR1{75}=q{reid allocation latch};                                 
$latch_name_11gR1{76}=q{queued dump request};                                   
$latch_name_11gR1{77}=q{global hanganlyze operation};                           
$latch_name_11gR1{78}=q{ges process table freelist};                            
$latch_name_11gR1{79}=q{ges process parent latch};                              
$latch_name_11gR1{80}=q{ges process hash list};                                 
$latch_name_11gR1{81}=q{ges resource table freelist};                           
$latch_name_11gR1{82}=q{ges caches resource lists};                             
$latch_name_11gR1{83}=q{ges resource hash list};                                
$latch_name_11gR1{84}=q{ges resource scan list};                                
$latch_name_11gR1{85}=q{ges s-lock bitvec freelist};                            
$latch_name_11gR1{86}=q{ges enqueue table freelist};                            
$latch_name_11gR1{87}=q{ges timeout list};                                      
$latch_name_11gR1{88}=q{ges deadlock list};                                     
$latch_name_11gR1{89}=q{ges statistic table};                                   
$latch_name_11gR1{90}=q{ges synchronous data};                                  
$latch_name_11gR1{91}=q{KJC message pool free list};                            
$latch_name_11gR1{92}=q{KJC receiver ctx free list};                            
$latch_name_11gR1{93}=q{KJC snd proxy ctx free list};                           
$latch_name_11gR1{94}=q{KJC destination ctx free list};                         
$latch_name_11gR1{95}=q{KJC receiver queue access list};                        
$latch_name_11gR1{96}=q{KJC snd proxy queue access list};                       
$latch_name_11gR1{97}=q{KJC global resend message queue};                       
$latch_name_11gR1{98}=q{KJCT receiver queue access};                            
$latch_name_11gR1{99}=q{KJCT flow control latch};                               
$latch_name_11gR1{100}=q{KJC global post event buffer};                         
$latch_name_11gR1{101}=q{ges domain table};                                     
$latch_name_11gR1{102}=q{ges group table};                                      
$latch_name_11gR1{103}=q{gcs resource hash};                                    
$latch_name_11gR1{104}=q{gcs opaque info freelist};                             
$latch_name_11gR1{105}=q{gcs resource freelist};                                
$latch_name_11gR1{106}=q{gcs resource scan list};                               
$latch_name_11gR1{107}=q{gcs resource validate list};                           
$latch_name_11gR1{108}=q{gcs domain validate latch};                            
$latch_name_11gR1{109}=q{gcs shadows freelist};                                 
$latch_name_11gR1{110}=q{gcs commit scn state};                                 
$latch_name_11gR1{111}=q{name-service entry};                                   
$latch_name_11gR1{112}=q{name-service request queue};                           
$latch_name_11gR1{113}=q{name-service pending queue};                           
$latch_name_11gR1{114}=q{name-service namespace bucket};                        
$latch_name_11gR1{115}=q{name-service memory objects};                          
$latch_name_11gR1{116}=q{name-service namespace objects};                       
$latch_name_11gR1{117}=q{name-service request};                                 
$latch_name_11gR1{118}=q{name-service memory recovery};                         
$latch_name_11gR1{119}=q{gcs remastering latch};                                
$latch_name_11gR1{120}=q{gcs partitioned table hash};                           
$latch_name_11gR1{121}=q{gcs pcm hashed value bucket hash};                     
$latch_name_11gR1{122}=q{gcs remaster request queue};                           
$latch_name_11gR1{123}=q{recovery domain freelist};                             
$latch_name_11gR1{124}=q{recovery domain hash list};                            
$latch_name_11gR1{125}=q{ges value block free list};                            
$latch_name_11gR1{126}=q{Testing};                                              
$latch_name_11gR1{127}=q{KMG MMAN ready and startup request latch};             
$latch_name_11gR1{128}=q{KMG resize request state object freelist};             
$latch_name_11gR1{129}=q{Memory Management Latch};                              
$latch_name_11gR1{130}=q{file number translation table};                        
$latch_name_11gR1{131}=q{mostly latch-free SCN};                                
$latch_name_11gR1{132}=q{lgwr LWN SCN};                                         
$latch_name_11gR1{133}=q{redo on-disk SCN};                                     
$latch_name_11gR1{134}=q{ping redo on-disk SCN};                                
$latch_name_11gR1{135}=q{Consistent RBA};                                       
$latch_name_11gR1{136}=q{cache buffers lru chain};                              
$latch_name_11gR1{137}=q{buffer pool};                                          
$latch_name_11gR1{138}=q{multiple dbwriter suspend};                            
$latch_name_11gR1{139}=q{active checkpoint queue latch};                        
$latch_name_11gR1{140}=q{checkpoint queue latch};                               
$latch_name_11gR1{141}=q{cache buffers chains};                                 
$latch_name_11gR1{142}=q{cache buffer handles};                                 
$latch_name_11gR1{143}=q{multiblock read objects};                              
$latch_name_11gR1{144}=q{cache protection latch};                               
$latch_name_11gR1{145}=q{block corruption recovery state};                      
$latch_name_11gR1{146}=q{tablespace key chain};                                 
$latch_name_11gR1{147}=q{cache table scan latch};                               
$latch_name_11gR1{148}=q{simulator lru latch};                                  
$latch_name_11gR1{149}=q{simulator hash latch};                                 
$latch_name_11gR1{150}=q{sim partition latch};                                  
$latch_name_11gR1{151}=q{state object free list};                               
$latch_name_11gR1{152}=q{object queue header operation};                        
$latch_name_11gR1{153}=q{object queue header heap};                             
$latch_name_11gR1{154}=q{Real time apply boundary};                             
$latch_name_11gR1{155}=q{LGWR NS Write};                                        
$latch_name_11gR1{156}=q{archive control};                                      
$latch_name_11gR1{157}=q{archive process latch};                                
$latch_name_11gR1{158}=q{managed standby latch};                                
$latch_name_11gR1{159}=q{alert log latch};                                      
$latch_name_11gR1{160}=q{SGA kcrrgap latch};                                    
$latch_name_11gR1{161}=q{SGA kcrrpinfo latch};                                  
$latch_name_11gR1{162}=q{SGA kcrrssncpl latch};                                 
$latch_name_11gR1{163}=q{SGA kcrrlatmscnl latch};                               
$latch_name_11gR1{164}=q{SGA kcrrlac latch};                                    
$latch_name_11gR1{165}=q{FAL subheap alocation};                                
$latch_name_11gR1{166}=q{FAL request queue};                                    
$latch_name_11gR1{167}=q{Managed Standby Recovery State};                       
$latch_name_11gR1{168}=q{redo writing};                                         
$latch_name_11gR1{169}=q{redo copy};                                            
$latch_name_11gR1{170}=q{redo allocation};                                      
$latch_name_11gR1{171}=q{readable standby influx scn};                          
$latch_name_11gR1{172}=q{readredo stats and histogram};                         
$latch_name_11gR1{173}=q{OS file lock latch};                                   
$latch_name_11gR1{174}=q{gc element};                                           
$latch_name_11gR1{175}=q{gc checkpoint};                                        
$latch_name_11gR1{176}=q{loader state object freelist};                         
$latch_name_11gR1{177}=q{begin backup scn array};                               
$latch_name_11gR1{178}=q{krbmrosl};                                             
$latch_name_11gR1{179}=q{logminer work area};                                   
$latch_name_11gR1{180}=q{logminer context allocation};                          
$latch_name_11gR1{181}=q{logical standby cache};                                
$latch_name_11gR1{182}=q{logical standby view};                                 
$latch_name_11gR1{183}=q{media recovery process out of buffers};                
$latch_name_11gR1{184}=q{mapped buffers lru chain};                             
$latch_name_11gR1{185}=q{Media rcv so alloc latch};                             
$latch_name_11gR1{186}=q{parallel recoverable recovery};                        
$latch_name_11gR1{187}=q{block media rcv so alloc latch};                       
$latch_name_11gR1{188}=q{readable standby metadata redo cache};                 
$latch_name_11gR1{189}=q{change tracking state change latch};                   
$latch_name_11gR1{190}=q{change tracking optimization SCN};                     
$latch_name_11gR1{191}=q{change tracking consistent SCN};                       
$latch_name_11gR1{192}=q{lock DBA buffer during media recovery};                
$latch_name_11gR1{193}=q{lock new checkpoint scn during media recovery};        
$latch_name_11gR1{194}=q{reservation so alloc latch};                           
$latch_name_11gR1{195}=q{Reserved Space Latch};                                 
$latch_name_11gR1{196}=q{flashback marker cache};                               
$latch_name_11gR1{197}=q{flashback FBA barrier};                                
$latch_name_11gR1{198}=q{flashback SCN barrier};                                
$latch_name_11gR1{199}=q{hint flashback FBA barrier};                           
$latch_name_11gR1{200}=q{flashback hint SCN barrier};                           
$latch_name_11gR1{201}=q{flashback allocation};                                 
$latch_name_11gR1{202}=q{flashback mapping};                                    
$latch_name_11gR1{203}=q{flashback copy};                                       
$latch_name_11gR1{204}=q{flashback sync request};                               
$latch_name_11gR1{205}=q{Minimum flashback SCN latch};                          
$latch_name_11gR1{206}=q{Block new check invariant rollback SCN latch};         
$latch_name_11gR1{207}=q{file deallocation SCN cache};                          
$latch_name_11gR1{208}=q{Transportable DB Context Latch};                       
$latch_name_11gR1{209}=q{cv free list lock};                                    
$latch_name_11gR1{210}=q{cv apply list lock};                                   
$latch_name_11gR1{211}=q{io pool granule metadata list};                        
$latch_name_11gR1{212}=q{io pool granule list};                                 
$latch_name_11gR1{213}=q{dml lock allocation};                                  
$latch_name_11gR1{214}=q{DML lock allocation};                                  
$latch_name_11gR1{215}=q{list of block allocation};                             
$latch_name_11gR1{216}=q{transaction allocation};                               
$latch_name_11gR1{217}=q{dummy allocation};                                     
$latch_name_11gR1{218}=q{transaction branch allocation};                        
$latch_name_11gR1{219}=q{commit callback allocation};                           
$latch_name_11gR1{220}=q{undo global data};                                     
$latch_name_11gR1{221}=q{corrupted undo seg lock};                              
$latch_name_11gR1{222}=q{MinActiveScn Latch};                                   
$latch_name_11gR1{223}=q{parallel txn reco latch};                              
$latch_name_11gR1{224}=q{intra txn parallel recovery};                          
$latch_name_11gR1{225}=q{Undo Hint Latch};                                      
$latch_name_11gR1{226}=q{resumable state object};                               
$latch_name_11gR1{227}=q{In memory undo latch};                                 
$latch_name_11gR1{228}=q{KTF sga latch};                                        
$latch_name_11gR1{229}=q{MQL Tracking Latch};                                   
$latch_name_11gR1{230}=q{Change Notification Hash table latch};                 
$latch_name_11gR1{231}=q{Change Notification Latch};                            
$latch_name_11gR1{232}=q{flashback archiver latch};                             
$latch_name_11gR1{233}=q{change notification client cache latch};               
$latch_name_11gR1{234}=q{sort extent pool};                                     
$latch_name_11gR1{235}=q{lob segment hash table latch};                         
$latch_name_11gR1{236}=q{lob segment query latch};                              
$latch_name_11gR1{237}=q{lob segment dispenser latch};                          
$latch_name_11gR1{238}=q{shrink stat allocation latch};                         
$latch_name_11gR1{239}=q{file cache latch};                                     
$latch_name_11gR1{240}=q{ktm global data};                                      
$latch_name_11gR1{241}=q{space background SGA latch};                           
$latch_name_11gR1{242}=q{space background task latch};                          
$latch_name_11gR1{243}=q{space background state object latch};                  
$latch_name_11gR1{244}=q{sequence cache};                                       
$latch_name_11gR1{245}=q{temp lob duration state obj allocation};               
$latch_name_11gR1{246}=q{kssmov protection latch};                              
$latch_name_11gR1{247}=q{File State Object Pool Parent Latch};                  
$latch_name_11gR1{248}=q{Write State Object Pool Parent Latch};                 
$latch_name_11gR1{249}=q{deferred cleanup latch};                               
$latch_name_11gR1{250}=q{domain validation update latch};                       
$latch_name_11gR1{251}=q{kdlx hb parent latch};                                 
$latch_name_11gR1{252}=q{Locator state objects pool parent latch};              
$latch_name_11gR1{253}=q{row cache objects};                                    
$latch_name_11gR1{254}=q{KQF runtime table column alloc};                       
$latch_name_11gR1{255}=q{QOL Name Generation Latch};                            
$latch_name_11gR1{256}=q{dictionary lookup};                                    
$latch_name_11gR1{257}=q{kks stats};                                            
$latch_name_11gR1{258}=q{kkae edition name cache};                              
$latch_name_11gR1{259}=q{KKCN reg stat latch};                                  
$latch_name_11gR1{260}=q{KKCN grp reg latch};                                   
$latch_name_11gR1{261}=q{KKCN grp data latch};                                  
$latch_name_11gR1{262}=q{global KZLD latch for mem in SGA};                     
$latch_name_11gR1{263}=q{cost function};                                        
$latch_name_11gR1{264}=q{user lock};                                            
$latch_name_11gR1{265}=q{Policy Refresh Latch};                                 
$latch_name_11gR1{266}=q{Policy Hash Table Latch};                              
$latch_name_11gR1{267}=q{OLS label cache};                                      
$latch_name_11gR1{268}=q{instance information};                                 
$latch_name_11gR1{269}=q{policy information};                                   
$latch_name_11gR1{270}=q{global ctx hash table latch};                          
$latch_name_11gR1{271}=q{Role grants to users};                                 
$latch_name_11gR1{272}=q{Role graph};                                           
$latch_name_11gR1{273}=q{Security Class Hashtable};                             
$latch_name_11gR1{274}=q{global tx hash mapping};                               
$latch_name_11gR1{275}=q{k2q lock allocation};                                  
$latch_name_11gR1{276}=q{k2q global data latch};                                
$latch_name_11gR1{277}=q{shared pool};                                          
$latch_name_11gR1{278}=q{library cache load lock};                              
$latch_name_11gR1{279}=q{Token Manager};                                        
$latch_name_11gR1{280}=q{cas latch};                                            
$latch_name_11gR1{281}=q{rm cas latch};                                         
$latch_name_11gR1{282}=q{resmgr:actses change state};                           
$latch_name_11gR1{283}=q{resmgr:actses change group};                           
$latch_name_11gR1{284}=q{resmgr:session queuing};                               
$latch_name_11gR1{285}=q{resmgr:active threads};                                
$latch_name_11gR1{286}=q{resmgr:schema config};                                 
$latch_name_11gR1{287}=q{resmgr:vc list latch};                                 
$latch_name_11gR1{288}=q{resmgr:incr/decr stats};                               
$latch_name_11gR1{289}=q{resmgr:method mem alloc latch};                        
$latch_name_11gR1{290}=q{resmgr:plan CPU method};                               
$latch_name_11gR1{291}=q{resmgr:resource group CPU method};                     
$latch_name_11gR1{292}=q{QMT};                                                  
$latch_name_11gR1{293}=q{shared pool simulator};                                
$latch_name_11gR1{294}=q{shared pool sim alloc};                                
$latch_name_11gR1{295}=q{Streams Generic};                                      
$latch_name_11gR1{296}=q{Shared B-Tree};                                        
$latch_name_11gR1{297}=q{Memory Queue};                                         
$latch_name_11gR1{298}=q{Memory Queue Subscriber};                              
$latch_name_11gR1{299}=q{Memory Queue Message Subscriber #1};                   
$latch_name_11gR1{300}=q{Memory Queue Message Subscriber #2};                   
$latch_name_11gR1{301}=q{Memory Queue Message Subscriber #3};                   
$latch_name_11gR1{302}=q{Memory Queue Message Subscriber #4};                   
$latch_name_11gR1{303}=q{pesom_hash_node};                                      
$latch_name_11gR1{304}=q{pesom_free_list};                                      
$latch_name_11gR1{305}=q{pesom_heap_alloc};                                     
$latch_name_11gR1{306}=q{peshm};                                                
$latch_name_11gR1{307}=q{Mutex};                                                
$latch_name_11gR1{308}=q{Mutex Stats};                                          
$latch_name_11gR1{309}=q{pebof_rrv};                                            
$latch_name_11gR1{310}=q{ODM-NFS:Global file structure};                        
$latch_name_11gR1{311}=q{KGNFS-NFS:SHM structure};                              
$latch_name_11gR1{312}=q{KGNFS-NFS:SVR LIST };                                  
$latch_name_11gR1{313}=q{SGA heap creation lock};                               
$latch_name_11gR1{314}=q{SGA heap locks};                                       
$latch_name_11gR1{315}=q{SGA pool creation lock};                               
$latch_name_11gR1{316}=q{SGA pool locks};                                       
$latch_name_11gR1{317}=q{SGA bucket locks};                                     
$latch_name_11gR1{318}=q{SGA blob lock};                                        
$latch_name_11gR1{319}=q{SGA blob parent};                                      
$latch_name_11gR1{320}=q{kgb latch};                                            
$latch_name_11gR1{321}=q{kgb parent};                                           
$latch_name_11gR1{322}=q{SGA table lock};                                       
$latch_name_11gR1{323}=q{Event Group Locks};                                    
$latch_name_11gR1{324}=q{SGA slab metadata lock};                               
$latch_name_11gR1{325}=q{Sage HT Latch};                                        
$latch_name_11gR1{326}=q{shared server configuration};                          
$latch_name_11gR1{327}=q{session timer};                                        
$latch_name_11gR1{328}=q{parameter list};                                       
$latch_name_11gR1{329}=q{presentation list};                                    
$latch_name_11gR1{330}=q{address list};                                         
$latch_name_11gR1{331}=q{end-point list};                                       
$latch_name_11gR1{332}=q{shared server info};                                   
$latch_name_11gR1{333}=q{dispatcher info};                                      
$latch_name_11gR1{334}=q{virtual circuit buffers};                              
$latch_name_11gR1{335}=q{virtual circuit queues};                               
$latch_name_11gR1{336}=q{virtual circuits};                                     
$latch_name_11gR1{337}=q{virtual circuit holder};                               
$latch_name_11gR1{338}=q{kmcptab latch};                                        
$latch_name_11gR1{339}=q{kmcpvec latch};                                        
$latch_name_11gR1{340}=q{cp pool array latch};                                  
$latch_name_11gR1{341}=q{cp cmon array latch};                                  
$latch_name_11gR1{342}=q{cp server array latch};                                
$latch_name_11gR1{343}=q{cp server hash latch};                                 
$latch_name_11gR1{344}=q{cp cso latch};                                         
$latch_name_11gR1{345}=q{cp pool latch};                                        
$latch_name_11gR1{346}=q{cp cmon/server latch};                                 
$latch_name_11gR1{347}=q{cp holder latch};                                      
$latch_name_11gR1{348}=q{cp sga latch};                                         
$latch_name_11gR1{349}=q{JOX SGA heap latch};                                   
$latch_name_11gR1{350}=q{JOX JIT latch};                                        
$latch_name_11gR1{351}=q{job_queue_processes parameter latch};                  
$latch_name_11gR1{352}=q{job workq parent latch};                               
$latch_name_11gR1{353}=q{job_queue_processes free list latch};                  
$latch_name_11gR1{354}=q{query server process};                                 
$latch_name_11gR1{355}=q{query server freelists};                               
$latch_name_11gR1{356}=q{error message lists};                                  
$latch_name_11gR1{357}=q{process queue};                                        
$latch_name_11gR1{358}=q{process queue reference};                              
$latch_name_11gR1{359}=q{parallel query stats};                                 
$latch_name_11gR1{360}=q{business card};                                        
$latch_name_11gR1{361}=q{parallel query alloc buffer};                          
$latch_name_11gR1{362}=q{hash table modification latch};                        
$latch_name_11gR1{363}=q{hash table column usage latch};                        
$latch_name_11gR1{364}=q{constraint object allocation};                         
$latch_name_11gR1{365}=q{device information};                                   
$latch_name_11gR1{366}=q{temporary table state object allocation};              
$latch_name_11gR1{367}=q{internal temp table object number allocation latch};   
$latch_name_11gR1{368}=q{SQL memory manager latch};                             
$latch_name_11gR1{369}=q{SQL memory manager workarea list latch};               
$latch_name_11gR1{370}=q{compile environment latch};                            
$latch_name_11gR1{371}=q{Bloom filter list latch};                              
$latch_name_11gR1{372}=q{Bloom Filter SGA latch};                               
$latch_name_11gR1{373}=q{Result Cache: Latch};                                  
$latch_name_11gR1{374}=q{Result Cache: SO Latch};                               
$latch_name_11gR1{375}=q{kupp process latch};                                   
$latch_name_11gR1{376}=q{pass worker exception to master};                      
$latch_name_11gR1{377}=q{datapump job fixed tables latch};                      
$latch_name_11gR1{378}=q{datapump attach fixed tables latch};                   
$latch_name_11gR1{379}=q{process};                                              
$latch_name_11gR1{380}=q{TXN SGA};                                              
$latch_name_11gR1{381}=q{STREAMS LCR};                                          
$latch_name_11gR1{382}=q{STREAMS Pool Advisor};                                 
$latch_name_11gR1{383}=q{kokc descriptor allocation latch};                     
$latch_name_11gR1{384}=q{ncodef allocation latch};                              
$latch_name_11gR1{385}=q{NLS data objects};                                     
$latch_name_11gR1{386}=q{kpon job info latch};                                  
$latch_name_11gR1{387}=q{kpon sga structure};                                   
$latch_name_11gR1{388}=q{reg$ timeout service time};                            
$latch_name_11gR1{389}=q{KPON ksr channel latch};                               
$latch_name_11gR1{390}=q{EMON slave state object latch};                        
$latch_name_11gR1{391}=q{session state list latch};                             
$latch_name_11gR1{392}=q{kpplsSyncStateListSga: lock};                          
$latch_name_11gR1{393}=q{connection pool sga data lock};                        
$latch_name_11gR1{394}=q{message enqueue sync latch};                           
$latch_name_11gR1{395}=q{image handles of buffered messages latch};             
$latch_name_11gR1{396}=q{kwqi:kchunk latch};                                    
$latch_name_11gR1{397}=q{KWQP Prop Status};                                     
$latch_name_11gR1{398}=q{KWQS pqueue ctx latch};                                
$latch_name_11gR1{399}=q{KWQS pqsubs latch};                                    
$latch_name_11gR1{400}=q{AQ Propagation Scheduling Proc Table};                 
$latch_name_11gR1{401}=q{AQ Propagation Scheduling System Load};                
$latch_name_11gR1{402}=q{job queue sob latch};                                  
$latch_name_11gR1{403}=q{rules engine aggregate statistics};                    
$latch_name_11gR1{404}=q{rules engine rule set statistics};                     
$latch_name_11gR1{405}=q{rules engine rule statistics};                         
$latch_name_11gR1{406}=q{rules engine evaluation context statistics};           
$latch_name_11gR1{407}=q{enqueue sob latch};                                    
$latch_name_11gR1{408}=q{kwqbsgn:msghdr};                                       
$latch_name_11gR1{409}=q{kwqbsn:qxl};                                           
$latch_name_11gR1{410}=q{kwqbsn:qsga};                                          
$latch_name_11gR1{411}=q{kwqbcco:cco};                                          
$latch_name_11gR1{412}=q{bufq statistics};                                      
$latch_name_11gR1{413}=q{spilled messages latch};                               
$latch_name_11gR1{414}=q{queue sender's info. latch};                           
$latch_name_11gR1{415}=q{bq:time manger info latch};                            
$latch_name_11gR1{416}=q{qmn task queue latch};                                 
$latch_name_11gR1{417}=q{qmn task context latch};                               
$latch_name_11gR1{418}=q{qmn state object latch};                               
$latch_name_11gR1{419}=q{KWQMN job cache list latch};                           
$latch_name_11gR1{420}=q{KWQMN to-be-Stopped Buffer list Latch};                
$latch_name_11gR1{421}=q{fixed table rows for x$hs_session};                    
$latch_name_11gR1{422}=q{qm_init_sga};                                          
$latch_name_11gR1{423}=q{XDB unused session pool};                              
$latch_name_11gR1{424}=q{XDB used session pool};                                
$latch_name_11gR1{425}=q{XDB Config-1};                                         
$latch_name_11gR1{426}=q{XDB Config-2};                                         
$latch_name_11gR1{427}=q{XDB Config-3};                                         
$latch_name_11gR1{428}=q{qmtmrcsg_init};                                        
$latch_name_11gR1{429}=q{XML DB Events};                                        
$latch_name_11gR1{430}=q{XDB NFS Stateful SGA Latch};                           
$latch_name_11gR1{431}=q{qmne Export Table Latch};                              
$latch_name_11gR1{432}=q{XDB NFS Security Latch};                               
$latch_name_11gR1{433}=q{XDB Byte Lock SGA Latch};                              
$latch_name_11gR1{434}=q{XDB Mcache SGA Latch};                                 
$latch_name_11gR1{435}=q{XDB PL/SQL Support};                                   
$latch_name_11gR1{436}=q{DMON Work Queues Latch};                               
$latch_name_11gR1{437}=q{DMON Network Error List Latch};                        
$latch_name_11gR1{438}=q{RSM process latch};                                    
$latch_name_11gR1{439}=q{NSV command ID generation latch};                      
$latch_name_11gR1{440}=q{NSV creation/termination latch};                       
$latch_name_11gR1{441}=q{Request id generation latch};                          
$latch_name_11gR1{442}=q{Fast-Start Failover State Latch};                      
$latch_name_11gR1{443}=q{xscalc freelist};                                      
$latch_name_11gR1{444}=q{xssinfo freelist};                                     
$latch_name_11gR1{445}=q{AW SGA latch};                                         
$latch_name_11gR1{446}=q{ASM allocation};                                       
$latch_name_11gR1{447}=q{KFA SGA latch};                                        
$latch_name_11gR1{448}=q{buffer pin latch};                                     
$latch_name_11gR1{449}=q{KFC SGA latch};                                        
$latch_name_11gR1{450}=q{KFC LRU latch};                                        
$latch_name_11gR1{451}=q{KFC Hash Latch};                                       
$latch_name_11gR1{452}=q{KFC FX Hash Latch};                                    
$latch_name_11gR1{453}=q{ASM map headers};                                      
$latch_name_11gR1{454}=q{ASM map operation freelist};                           
$latch_name_11gR1{455}=q{ASM map operation hash table};                         
$latch_name_11gR1{456}=q{ASM map load waiting list};                            
$latch_name_11gR1{457}=q{KFK SGA Libload latch};                                
$latch_name_11gR1{458}=q{KFM allocation};                                       
$latch_name_11gR1{459}=q{KFMD SGA};                                             
$latch_name_11gR1{460}=q{ASM network background latch};                         
$latch_name_11gR1{461}=q{ASM network SGA latch};                                
$latch_name_11gR1{462}=q{ASM db client latch};                                  
$latch_name_11gR1{463}=q{ASM file locked extent latch};                         
$latch_name_11gR1{464}=q{ASM scan context latch};                               
$latch_name_11gR1{465}=q{ASM file allocation latch};                            
$latch_name_11gR1{466}=q{KFR redo allocation latch};                            
$latch_name_11gR1{467}=q{ASM rollback operations};                              
$latch_name_11gR1{468}=q{KFCL LE Freelist};                                     
$latch_name_11gR1{469}=q{KFCL Instance Latch};                                  
$latch_name_11gR1{470}=q{KFCL BX Freelist};                                     
$latch_name_11gR1{471}=q{ASM attribute latch};                                  
$latch_name_11gR1{472}=q{ASM Volume process latch};                             
$latch_name_11gR1{473}=q{ASM Volume SGA latch};                                 
$latch_name_11gR1{474}=q{OFS SGA Latch};                                        
$latch_name_11gR1{475}=q{server alert latch};                                   
$latch_name_11gR1{476}=q{generalized trace enabling latch};                     
$latch_name_11gR1{477}=q{statistics aggregation};                               
$latch_name_11gR1{478}=q{AWR Alerted Metric Element list};                      
$latch_name_11gR1{479}=q{threshold alerts latch};                               
$latch_name_11gR1{480}=q{WCR: kecu cas mem};                                    
$latch_name_11gR1{481}=q{WCR: ticker cache};                                    
$latch_name_11gR1{482}=q{Real-time plan statistics latch};                      
$latch_name_11gR1{483}=q{JS broadcast add buf latch};                           
$latch_name_11gR1{484}=q{JS broadcast drop buf latch};                          
$latch_name_11gR1{485}=q{JS broadcast kill buf latch};                          
$latch_name_11gR1{486}=q{JS broadcast load blnc latch};                         
$latch_name_11gR1{487}=q{JS broadcast autostart latch};                         
$latch_name_11gR1{488}=q{JS broadcast LW Job latch};                            
$latch_name_11gR1{489}=q{JS mem alloc latch};                                   
$latch_name_11gR1{490}=q{JS slv state obj latch};                               
$latch_name_11gR1{491}=q{JS queue state obj latch};                             
$latch_name_11gR1{492}=q{JS queue access latch};                                
$latch_name_11gR1{493}=q{JS Sh mem access};                                     
$latch_name_11gR1{494}=q{PL/SQL warning settings};                              
$latch_name_11gR1{495}=q{dbkea msgq latch};                                     

# extracts enqueue name from argument p1 (decimal) from WAIT 
# for enqueue in 10046 trace
sub enqueue_name($) {
	my ($p1)=@_;
	my $p1_hex=sprintf "%x", $p1;
	my $first_letter_hex= substr($p1_hex, 0, 2);
	my $second_letter_hex= substr($p1_hex, 2, 2);
	return chr(hex($first_letter_hex)) . chr(hex($second_letter_hex));
}

# extracts lock mode from lowest nibble of p1 and maps it
# to character represenation of the lock mode
sub get_lock_mode($) {
	my ($p1)=@_;
	# taken from Oracle Database Reference
	my %lock_mode_mapping=(
		1 => "N", # Null mode
		2 => "SS", # Sub-Share
		3 => "SE", # Sub-Exclusive
		4 => "S", # Share
		5 => "SSE", # Share/Sub-Exclusive
		6 => "X" # Exclusive
	);
	my $p1_hex=sprintf "%x", $p1;
	my $lock_mode=substr($p1_hex, 7, 1);
	return $lock_mode_mapping{$lock_mode};
}

sub usage() {
		printf STDERR "Usage: esqltrcprof.pl -v -r <ORACLE major release>.<version> -t <think time in milliseconds> <extended sql trace file>\n";
		printf STDERR "-v verbose output; includes instances of think time\n";
		printf STDERR "-r value must be in range 8.0 to 11.1\n";
		exit 1;
}

# print out per statement resource profile
# artificial hash keys for "think time" and "total CPU" must be maintained
sub per_stmt_res_prof($$$) {
	my ($wait_ela_ref, $wait_count_ref, $unit)=@_;
	my ($name_width, $sec_width, $count_width)=(40, 10, 8);
	printf("\n%-${name_width}s %${sec_width}s %${count_width}s\n", "Wait Event/CPU Usage/Think Time", "Duration", "Count");
	printf("%s %s %s\n", "-" x $name_width, "-" x $sec_width, "-" x $count_width);
	# keys of this hash are the wait event names, so $_ iterates over wait event names
	printf "%-${name_width}s %9.3fs %${count_width}d\n", $_, ($wait_ela_ref->{$_})/$unit, $wait_count_ref->{$_} for sort { $wait_ela_ref->{$b} <=> $wait_ela_ref->{$a} } keys %$wait_ela_ref;
}

sub per_stmt_results($$) {
	my ($hash_value, $unit)=@_;
	printf("\nHash Value: %s", $hash_value);
	printf(" - Total Elapsed Time (excluding think time): %.3fs\n", $stmt_list{$hash_value}->{TOTAL_ELAPSED}/$unit);
	if ( $stmt_list{$hash_value}->{SQL_ID} ne 'undefined' ) {
		printf("SQL Id: %s ", $stmt_list{$hash_value}->{SQL_ID});
	}
	printf("Module '%s' Action '%s' Dependency Level: %d\n", $stmt_list{$hash_value}->{MODULE}, $stmt_list{$hash_value}->{ACTION}, $stmt_list{$hash_value}->{DEP});
	printf("\n%s\n", $stmt_list{$hash_value}->{TEXT});
	my $heading_format="%-7s %8s %10s %10s %8s %8s %8s %8s\n";
	my $data_format="%-7s %8d %9.4fs %9.4fs %8d %8d %8d %8d\n";
	printf($heading_format, "DB Call", "Count", "Elapsed" ,"CPU", "Disk", "Query", "Current", "Rows");
	printf($heading_format, "-"x7, "-"x8, "-"x10, "-"x10, "-"x8, "-"x8,"-"x8,"-"x8,"-"x8);
	printf($data_format, "PARSE",
		$stmt_list{$hash_value}->{PARSE_COUNT},
		$stmt_list{$hash_value}->{PARSE_ELAPSED}/$unit,
		$stmt_list{$hash_value}->{PARSE_CPU}/$unit,
		$stmt_list{$hash_value}->{PARSE_DISK},
		$stmt_list{$hash_value}->{PARSE_CR},
		$stmt_list{$hash_value}->{PARSE_CUR_READ},
		$stmt_list{$hash_value}->{PARSE_ROWS});
	printf($data_format, "EXEC",
		$stmt_list{$hash_value}->{EXEC_COUNT},
		$stmt_list{$hash_value}->{EXEC_ELAPSED}/$unit,
		$stmt_list{$hash_value}->{EXEC_CPU}/$unit,
		$stmt_list{$hash_value}->{EXEC_DISK},
		$stmt_list{$hash_value}->{EXEC_CR},
		$stmt_list{$hash_value}->{EXEC_CUR_READ},
		$stmt_list{$hash_value}->{EXEC_ROWS});
	printf($data_format, "FETCH",
		$stmt_list{$hash_value}->{FETCH_COUNT},
		$stmt_list{$hash_value}->{FETCH_ELAPSED}/$unit,
		$stmt_list{$hash_value}->{FETCH_CPU}/$unit,
		$stmt_list{$hash_value}->{FETCH_DISK},
		$stmt_list{$hash_value}->{FETCH_CR},
		$stmt_list{$hash_value}->{FETCH_CUR_READ},
		$stmt_list{$hash_value}->{FETCH_ROWS});
	# ??? add WAIT statistics
        #WAIT_ELA  => $counter++,  # reference to a hash
        #WAIT_COUNT  => $counter++,  # reference to a hash
	#my $total_wait=0;
	#foreach $event_name (keys %$stmt_list{$hash_value}->{WAIT_ELA}) {
		#$total_wait+=
	#}
	printf($heading_format, "-"x7, "-"x8, "-"x10, "-"x10, "-"x8, "-"x8,"-"x8,"-"x8,"-"x8);
	printf($data_format, "Total",
		$stmt_list{$hash_value}->{PARSE_COUNT}+
		$stmt_list{$hash_value}->{EXEC_COUNT}+
		$stmt_list{$hash_value}->{FETCH_COUNT},
		$stmt_list{$hash_value}->{TOTAL_E_PARSE_EXEC_FETCH}/$unit,
		($stmt_list{$hash_value}->{PARSE_CPU}+
		$stmt_list{$hash_value}->{EXEC_CPU}+
		$stmt_list{$hash_value}->{FETCH_CPU})/$unit,
		$stmt_list{$hash_value}->{PARSE_DISK}+
		$stmt_list{$hash_value}->{EXEC_DISK}+
		$stmt_list{$hash_value}->{FETCH_DISK},
		$stmt_list{$hash_value}->{PARSE_CR}+
		$stmt_list{$hash_value}->{EXEC_CR}+
		$stmt_list{$hash_value}->{FETCH_CR},
		$stmt_list{$hash_value}->{PARSE_CUR_READ}+
		$stmt_list{$hash_value}->{EXEC_CUR_READ}+
		$stmt_list{$hash_value}->{FETCH_CUR_READ},
		$stmt_list{$hash_value}->{PARSE_ROWS}+
		$stmt_list{$hash_value}->{EXEC_ROWS}+
		$stmt_list{$hash_value}->{FETCH_ROWS});

	# add key to hash for representing the statements CPU usage
	$stmt_list{$hash_value}->{WAIT_ELA}->{"total CPU"}= $stmt_list{$hash_value}->{PARSE_CPU} +
		$stmt_list{$hash_value}->{EXEC_CPU} + $stmt_list{$hash_value}->{FETCH_CPU};
	# add key to hash for representing the CPU usage counter
	$stmt_list{$hash_value}->{WAIT_COUNT}->{"total CPU"}= $stmt_list{$hash_value}->{PARSE_COUNT} +
		$stmt_list{$hash_value}->{EXEC_COUNT} + $stmt_list{$hash_value}->{FETCH_COUNT};
	# print per statement resource profile
	# pass hash references for storing wait time per wait event name and wait count per wait event name
	per_stmt_res_prof($stmt_list{$hash_value}->{WAIT_ELA},$stmt_list{$hash_value}->{WAIT_COUNT}, $unit);

	if ( defined $stmt_list{$hash_value}->{STAT}) {
		# widths must match widths used when sprintf'ing STAT lines
		# should use variables to maintain in one place
		printf("\nExecution Plan:\n");
		printf("%4s %6s %8s %s\n", "Step", "Parent", "Rows", "Row Source");
		printf("%s %s %s %s\n", "-" x 4, "-" x 6, "-" x 8, "-" x 60);
		printf("%s", $stmt_list{$hash_value}->{STAT});
	}
}

sub init_stmt_record() {
	# allocate memory with anonymous hash reference
	my $ref={ };
	$ref->{PARSE_COUNT}=0;
	$ref->{PARSE_ELAPSED}=0;
	$ref->{PARSE_CPU}=0;
	$ref->{PARSE_DISK}=0;
	$ref->{PARSE_CR}=0;
	$ref->{PARSE_CUR_READ}=0;
	$ref->{PARSE_ROWS}=0;
	$ref->{EXEC_COUNT}=0;
	$ref->{EXEC_ELAPSED}=0;
	$ref->{EXEC_CPU}=0;
	$ref->{EXEC_DISK}=0;
	$ref->{EXEC_CR}=0;
	$ref->{EXEC_CUR_READ}=0;
	$ref->{EXEC_ROWS}=0;
	$ref->{FETCH_COUNT}=0;
	$ref->{FETCH_ELAPSED}=0;
	$ref->{FETCH_CPU}=0;
	$ref->{FETCH_DISK}=0;
	$ref->{FETCH_CR}=0;
	$ref->{FETCH_CUR_READ}=0;
	$ref->{FETCH_ROWS}=0;
	$ref->{TOTAL_E_PARSE_EXEC_FETCH}=0;
	$ref->{TOTAL_ELAPSED}=0;
	$ref->{STAT}=undef;
	# anonymous hashes to store list of wait events and counters
	$ref->{WAIT_ELA}={ };
	$ref->{WAIT_COUNT}={ };
	$ref->{SQL_ID}="undefined";
	$ref->{MODULE}="undefined";
	$ref->{ACTION}="undefined";
	$ref->{DEP}=-1;
	return $ref;
}

sub cursor_0_accounting($$$) {
	my ($stmt_rec_ref, $event_name, $ela_time)=@_;
	# add elapsed time to total elapsed time for this statement
	# used for sorting statements by total elapsed time
	# don't consider think time, since it does not indicate a problem with the server
	if ($event_name ne "think time") {
		$stmt_rec_ref->{TOTAL_ELAPSED}+=$ela_time;
	}
	# since waits for cursor 0 are not rolled up by any PARSE, EXEC, FETCH
	# must add ela to total elapsed time for trace file, i.e.
	# must increment R by waits on cursor 0, except
	# SQL*Net message from to client, since they are between calls and already
	# taken care of, careful! event_name may have changed to "think time"
	if ($event_name ne "SQL*Net message from client" && $event_name ne "SQL*Net message to client" && $event_name ne "think time") {
		$R+=$ela_time;
	}
}

my $argc=scalar(@ARGV);
if ( $argc < 1) {
	usage;
}
# handle command line switches
my $switch_present=substr($ARGV[0], 0, 1);
#printf "first character of first switch is %s\n", $switch_present;
my %switches;
if ( $switch_present eq "-" ) {
	my $result=getopts('r:vt:', \%switches);
	#print "result of getopts: '$result'\n";
	if ( ! $result >= 1 ) {
		usage;
	}
} 
# getopts modifies ARGV, leaves file name, but removes switches and args
$argc=scalar(@ARGV);
if ( $argc != 1) {
	usage;
}
my $input_file=$ARGV[0];

#foreach my $switch (keys %switches) {
#	print "$switch=$switches{$switch}\n";
#}

# unit of timing data (cs or micros). Initialize to microseconds and change if 8i or below trace file
my $unit=1000000;
my $i;
my $db_version;
my $db_major_rel=0;
# get oracle dbms version from trace file header
# some possible formats:
# Oracle Database 11g Enterprise Edition Release 11.1.0.6.0 - Production
# Oracle Database 10g Enterprise Edition Release 10.1.0.3.0 - Production
# Oracle9i Enterprise Edition Release 9.2.0.6.0 - Production
# trace file may not have a header, seen this when alter session set trace_file_identifier is used
open(INPUT_FILE, $input_file) or die "Could not open input file '$input_file'\n";
for ($i = 1; $i < 10; $i++) {
	$_=<INPUT_FILE>;
	#printf "line %d %s", $., $_;
	if (/Oracle.*Release (\d+)\.(\d+)\./i) {
		$db_version="$1.$2";
		$db_major_rel=$1;
		print "ORACLE version $db_version trace file. ";
		if ( $1 <=8 ) {
			# 8i timings are in centiseconds
			$unit=100;
			print "Timings are in centiseconds (1/100 sec)\n"
		} else {
			# 9i timings and above are in microseconds; unit initialized to microsec by default
			print "Timings are in microseconds (1/1000000 sec)\n"
		}
		last;
	}
}  
# check switch -r if no trace file header is present
# if a header is present, switch -r is ignored
if ($db_major_rel == 0) {
	if ( defined $switches{r} ) {
		$_=$switches{r};
		if (/(\d+)\.(\d+)/i) {
			$db_version="$1.$2";
			$db_major_rel=$1;
			print "Assuming ORACLE release $db_version trace file.\n";
		} else {
			printf(STDERR "Invalid specification of major release and version with switch -r.\n");
			usage;
		}
	} else {
		# if neither header nor switch is present exit with usage
		printf(STDERR "No trace file header found reading trace file up to line %d. ORACLE release unknown.\nPlease use switch -r to specify release\n", $.);
		usage;
	}
}
close(INPUT_FILE);
# think time
my $think_time_threshold;
if ( $db_major_rel >= 9 ) {
	$think_time_threshold=5000 * 1/$unit;  # 5000 microsec = 5ms
} else {
	# due to low resolution of timer in 8i (1 cs) the smallest usable threshold is 2cs
	$think_time_threshold=2 * 1/$unit; # 2cs = 20ms
}
# command line switch -t overrides default think time threshold
if ( defined $switches{t} ) {
	$think_time_threshold=$switches{t}/1000; # command line switch has unit ms or 1/1000 sec
}

# SQL net message from client > 0.005 sec considered think time
# 300000 microsec in 9i
# correct for think time by:
# compute average of SQL net message from cient
# replace ela for SQL*Net message from client with average for SQL*Net
# message from client below threshold times number of waits above
# threshold
my $action="(?:PARSE|EXEC|FETCH|UNMAP|SORT UNMAP)";

open(INPUT_FILE, $input_file);
while (<INPUT_FILE>) {
	if ( $debug_level >= 1) {
	printf "main loop: line %d %s", $., $_;
	}
	# example 9i WAIT:
	# WAIT #1: nam='SQL*Net message to client' ela= 7 p1=1111838976 p2=1 p3=0
	# example 10g WAIT
	# WAIT #8: nam='pipe get' ela= 2929893 handle address=725303696 buffer length=4096 timeout=10 obj#=-1 tim=1157946767599586
	# this is old code for 9i format:
	# if (/^WAIT #(\d+): nam='([^']*)' ela=\s*(\d+)\s*p1=(\d+)\s*p2=(\d+)\s*p3=(\d+)/i) {
	# 10g has meaningful wait event parameter names. Parameter name ends when '=' is encountered
	# 10g also has obj#=12997 tim=1157853676305023 at the end of a WAIT entry
	# in 10g some wait event parameters may be negative, such that values must be matched with -?\d+. Examples:
	# WAIT #1: nam='Data file init write' ela= 11 count=-1 intr=32 timeout=2147483647 obj#=53077 tim=348053529807
	# WAIT #1: nam='Data file init write' ela= 24694 count=1 intr=256 timeout=-1 obj#=53077 tim=348053412059
	# WAIT entry
	if (/^WAIT #(\d+): nam='([^']*)' ela=\s*(\d+) \s*([^=]+)=\s*(-?\d+) \s*([^=]+)=\s*(-?\d+) \s*([^=]+)=\s*(-?\d+)/i) {
			#                             ^^^^^^^^^^
			#                             any string ending with '='
			#print "found WAIT event\n";
			$cursor_nr=$1;
			$event_name=$2;
			$ela_time=$3;
			$p1_text=$4;
			$p1_value=$5;
			$p2_text=$6;
			$p2_value=$7;
			$p3_text=$8;
			$p3_value=$9;
			if ($db_major_rel >= 10) {
				# extract object involved in WAIT
				if (/.* obj#=(-?\d+) tim=(\d+)/i) {
					$obj_id=$1;
					$tim=$2;
					# t0 is first time stamp of any database call
					if ($t0 == 0) {
						$t0=$tim;
					}
					# t1 is last time stamp of any database call
					$t1=$tim;
				}
			}
			if ( $debug_level > 0) {
				printf "cursor_nr '%d' event_name '%s' ela_time='%d' p1_text=p1_value '%s'='%d' p2_text=p2_value '%s'='%d' p3_text=p3_value '%s'='%d'", $cursor_nr, $event_name, $ela_time, $p1_text, $p1_value, $p2_text ,$p2_value ,$p3_text, $p3_value;
				if ($db_major_rel >= 10) {
					printf(" obj#='%s' tim='%s'", $obj_id, $tim);
				}
				print "\n\n";
			}
			# add ela to aggregate response time, only if this type of wait event occurs between
			# database calls and not within
			# according to Millsap, wait events between database calls include the following
			# SQL*Net message from client, SQL*Net message to client, single-task message
			# pipe get, rdbms ipc message, pmon timer, smon timer
			#  
			if ($event_name eq "SQL*Net message from client") {
				# this is elapsed time between database calls
				if ($ela_time/$unit > $think_time_threshold) {
					# if larger than threshold then accounted as think time
					# simply change event name
					$event_name="think time";
					if ( defined $switches{v} ) {
						printf "Found %.3f s think time (Line %d, Module '%s' Action '%s')\n", $ela_time/$unit, $., $curr_app_mod, $curr_app_act;
					}
				}
				# think time is also elapsed time, so add both types of SQL*Net message from
				# client ela values to sum_ela
				# increment response time
				$R+=$ela_time;

=for commentary

according to Millsap, Optimizing Oracle Performace, page 88 these are
between database call waits:
pmon timer
rdbms ipc message
smon timer
pipe get
single-task message
I bet single-task message is no longer used since only two-task implementation
of ORACLE exists, even on VMS, have personally never seen it
pretty sure I saw 'rdbms ipc message' in slow truncates in 9i, so it might
happen within database call. See bug 5257478. It's CKPT that waits for it, so
also not relevent to applications which are served by foreground processes (which can't
get background process waits).
pmon timer and smon timer will never be seen in a foreground process either.

In all my testing I have never seen pipe get between database calls. I believe that it is
impossible, since you need to make a PL/SQL call with DBMS_PIPE to wait for pipe get,
the example below which calls DBMS_PIPE with a timeout of 10 seconds clearly shows that
pipe get is rolled up into the EXEC step of the cursor which ran DBMS_PIPE
PARSE #8:c=0,e=14,p=0,cr=0,cu=0,mis=0,r=0,dep=0,og=1,tim=1157946762714852
WAIT #8: nam='pipe get' ela= 1954017 handle address=725303696 buffer length=4096 timeout=10 obj#=-1 tim=1157946764669619
WAIT #8: nam='pipe get' ela= 2929893 handle address=725303696 buffer length=4096 timeout=10 obj#=-1 tim=1157946767599586
WAIT #8: nam='pipe get' ela= 3907429 handle address=725303696 buffer length=4096 timeout=10 obj#=-1 tim=1157946771507132
*** 2007-07-29 21:31:35.024
WAIT #8: nam='pipe get' ela= 977890 handle address=725303696 buffer length=4096 timeout=10 obj#=-1 tim=1157946772485117
WAIT #8: nam='SQL*Net message to client' ela= 7 driver id=1650815232 #bytes=1 p3=0 obj#=-1 tim=1157946772485597
EXEC #8:c=0,e=9770460,p=0,cr=0,cu=0,mis=0,r=1,dep=0,og=1,tim=1157946772485632

LOBs are handled without PARSING IN CURSOR and EXEC (at least when used from Perl DBI through OCI. 
When commit occurs after LOB operation, cursor 0
is in trace file. This cannot be rolled up into any EXEC call, since there is none for
cursor 0. So log file sync for cursor 0 might have to be added to R.

direct path write/read due to uncached LOB is not rolled up into EXEC or anything else in this
10g trace from Perl DBI (same with DBMS_LOB)
WAIT #8: nam='SQL*Net more data from client' ela= 0 driver id=1413697536 #bytes=57 p3=0 obj#=12997 tim=1157853676295207
WAIT #8: nam='SQL*Net more data from client' ela= 0 driver id=1413697536 #bytes=104 p3=0 obj#=12997 tim=1157853676295235
WAIT #8: nam='direct path write' ela= 650 file number=4 first dba=8453 block cnt=1 obj#=12997 tim=1157853676297300
WAIT #8: nam='direct path write' ela= 19 file number=4 first dba=8334 block cnt=1 obj#=12997 tim=1157853676297486

=cut

			#all other wait events between database calls handled here 

			} elsif ($event_name eq "SQL*Net message to client") {
				# this is elapsed time between database calls
				# increment response time
				$R+=$ela_time;
			} elsif ($event_name eq "db file sequential read") {
				$physical_reads{sequential}+=$p3_value;
			} elsif ($event_name eq "db file scattered read") {
				$physical_reads{scattered}+=$p3_value;
			} elsif ($event_name eq "latch free") {
				# Oracle9i format:
				# WAIT #1: nam='latch free' ela= 6041 p1=2048023956 p2=158 p3=0
				# WAIT #1: nam='latch free' ela= 10808 p1=2048023756 p2=157 p3=1
				# according to database reference p3 is:
				# tries A count of the number of times the process tried to get the latch (slow
				# with spinning) and the process has to sleep
				$latch_free_waits{$p2_value}++;
				$latch_sleeps{$p2_value}+=$p3_value;
			} elsif ($event_name eq "enqueue") {
				$enqueue_name=enqueue_name($p1_value);
				$lock_mode=get_lock_mode($p1_value);
				$enqueue_waits{"$enqueue_name" . "," . "$lock_mode"}++;
				$enqueue_wait_time{"$enqueue_name" . "," . "$lock_mode"}+=$ela_time;
			} elsif (substr($event_name, 0, 6) eq "latch:") {
				# Oracle10g format:
				# WAIT #1: nam='latch: cache buffers chains' ela= 53 address=1769735128 number=122 tries=0 obj#=53077 tim=348055848943
				# WAIT #1: nam='latch: library cache' ela= 7 address=1757166424 number=214 tries=1 obj#=53077 tim=348056360671
				# WAIT #1: nam='latch: enqueue hash chains' ela= 8 address=1772419384 number=19 tries=1 obj#=53077 tim=348058725263
				# WAIT #1: nam='latch: library cache pin' ela= 121 address=1757166736 number=216 tries=1 obj#=53077 tim=348059520958
				$latch_free_waits{$p2_value}++;
				$latch_sleeps{$p2_value}+=$p3_value;
				if ( $debug_level > 1) {
					printf("10g+ latch wait: number %s, tries %s\n", $p2_value, $p3_value);
				}
			} elsif (substr($event_name, 0, 4) eq "enq:") {
				# 10g enqueue wait:
				# WAIT #1: nam='enq: TX - index contention' ela= 3 name|mode=1415053316 usn<<16 | slot=589825 sequence=542 obj#=53077 tim=348052808767
				# WAIT #1: nam='enq: HW - contention' ela= 10493 name|mode=1213661190 table space #=1 block=8388665 obj#=53077 tim=348053166621
				$enqueue_name=enqueue_name($p1_value);
				$lock_mode=get_lock_mode($p1_value);
				$enqueue_waits{"$enqueue_name" . "," . "$lock_mode"}++;
				$enqueue_wait_time{"$enqueue_name" . "," . "$lock_mode"}+=$ela_time;
				if ( $debug_level > 1) {
					printf("10g+ enqueue wait: enqueue name '%s' lock mode '%s'\n", $enqueue_name, $lock_mode);
				}
			}
			# accounting for all wait events, no matter what type (within or in between call)
			$ela{"$event_name"}+=$ela_time;
			$occurrences{$event_name}++;
			$sum_ela+=$ela_time;
			# application instrumentation
			$ela_per_app_mod{$curr_app_mod}+=$ela_time;
			$ela_per_app_mod_act{$curr_app_mod.$curr_app_act}+=$ela_time;
			# per statement accounting
			# get corresponding hash value for per statement accounting
			if ( ! defined $cursor_to_hv{$cursor_nr}) {
				if( $cursor_nr==$unknown_cursor_nr) {
					printf(STDERR "Warning: WAIT event '%s' for cursor %d at line %d without prior PARSING IN CURSOR #%d - all waits for cursor 0 attributed to default unknown statement with hash value -1\n", $event_name, $cursor_nr, $., $cursor_nr);
					# apparently only WAIT entries for cursor 0 are possible
					# none of my test trace files contain PARSE #0, EXEC #0 or FETCH #0
					# use record for cursor 0
					# call init_stmt_record to init record for statement, returns hash ref
					my $cur_stmt=init_stmt_record();
					$cur_stmt->{TEXT}="Cursor 0 - unknown statement (default container for any trace file entries relating to cursor 0)";
					# add to statement list using reserved hash value -1
					$hash_value=-1;
					$stmt_list{$hash_value}=$cur_stmt;
					# must set mapping from cursor number to hash value
					$cursor_to_hv{$cursor_nr}=$hash_value;
					# do accounting for cursor 0. data structures have been initialized above
					# hash value was set to -1
					$stmt_list{$hash_value}->{WAIT_ELA}->{$event_name}+=$ela_time;
					$stmt_list{$hash_value}->{WAIT_COUNT}->{$event_name}++;
					# special treatment for cursor 0 - must rollup "manually"
					# sub called modifies TOTAL_ELAPSED for cursor 0
					cursor_0_accounting($stmt_list{$hash_value}, $event_name, $ela_time);
				} else {
					printf(STDERR "Warning: WAIT event '%s' for cursor %d at line %d without prior PARSING IN CURSOR #%d - ignored for per statement response time accounting\n", $event_name, $cursor_nr, $., $cursor_nr);
				}
			} else {
				$hash_value=$cursor_to_hv{$cursor_nr};

=for commentary

				theoretically all waits except those classified as in between database calls
				should be rolled up into either PARSE, EXEC or FETCH
				at least with LOBs and direct path write this does not happen
				this trace from DBMS_LOB did not even contain a PARSE for cursor 8, although
				trace was enabled with dbms_monitor right after connecting:
				$ grep direct /opt/oracle/obase/admin/TEN/udump/ten2_ora_11445.trc
				WAIT #8: nam='direct path write' ela= 649 file number=4 first dba=206 block cnt=1 obj#=12997 tim=1157963852590854
				WAIT #8: nam='direct path read' ela= 27 file number=4 first dba=206 block cnt=1 obj#=12997 tim=1157963852604591
				WAIT #8: nam='direct path write' ela= 400 file number=4 first dba=210 block cnt=1 obj#=12998 tim=1157963852609759
				$ grep '#8' /opt/oracle/obase/admin/TEN/udump/ten2_ora_11445.trc|cut -d: -f1|sort -u
WAIT #8


=cut
				
				$stmt_list{$hash_value}->{WAIT_ELA}->{$event_name}+=$ela_time;
				$stmt_list{$hash_value}->{WAIT_COUNT}->{$event_name}++;
				# special treatment for cursor 0 - must rollup "manually"
				# since there are no EXEC or other calls that cursor 0's waits might be rolled up into
				if( $cursor_nr==$unknown_cursor_nr) {
					# sub called modifies TOTAL_ELAPSED for cursor 0
					cursor_0_accounting($stmt_list{$hash_value}, $event_name, $ela_time);
				} elsif ($event_name eq "SQL*Net message from client" || $event_name eq "SQL*Net message to client") {
					# if this is a WAIT for a normal cursor and it's an in between database call wait, add
					# elapsed time to total elapsed time for this cursor, since these events are not rolled
					# up as part of PARSE, EXEC, FETCH, but contribute to total elapsed time attributed to
					# the cursor
					# should think time be added too? maybe not, since it does not indicate a problem in the
					# server
					$stmt_list{$hash_value}->{TOTAL_ELAPSED}+=$ela_time;
				}
			}
	}
		# parameters in v$event_name :
		# NAME                         PARAMETER1      PARAMETER2      PARAMETER3
		# -----------------------------------------------------------------------
		# db file sequential read      file#           block#          blocks
		# PL/SQL lock timer      duration
		# if parameterN is null, then pN is used just like in 9i
		# WAIT #16: nam='control file sequential read' ela= 64 file#=1 block#=1 blocks=1 obj#=23132 tim=9798691410438
		# WAIT #30: nam='db file scattered read' ela= 17613 file#=4 block#=8242 blocks=7 obj#=23044 tim=9798690266335
		# WAIT #2: nam='db file sequential read' ela= 68 file#=4 block#=306 blocks=1 obj#=22982 tim=9798464516858
		# WAIT #4: nam='log file sync' ela= 17397 buffer#=11486 p2=0 p3=0 obj#=23050 tim=9798673735976
		# WAIT #25: nam='PL/SQL lock timer' ela= 977601 duration=100 p2=0 p3=0 obj#=23130 tim=9798712050895
		# WAIT #2: nam='SQL*Net message from client' ela= 308644 driver id=1650815232 #bytes=1 p3=0 obj#=22982 tim=9798464828302
		# WAIT #2: nam='SQL*Net message to client' ela= 5 driver id=1650815232 #bytes=1 p3=0 obj#=22982 tim=9798464828659
		# WAIT #0: nam='SQL*Net more data from client' ela= 21 driver id=1650815232 #bytes=211 p3=0 obj#=23132 tim=9798691422124
		# WAIT #29: nam='SQL*Net more data to client' ela= 55 driver id=1650815232 #bytes=2008 p3=0 obj#=23136 tim=9798691457198
		# PARSING IN CURSOR #3 len=99 dep=1 uid=160 oct=3 lid=160 tim=9798661974900 hv=3531608154 ad='d4c8c940'
		# SELECT INSTANCE_NUMBER, INSTANCE_NAME , STARTUP_TIME, PARALLEL, VERSION , HOST_NAME FROM V$INSTANCE
		# END OF STMT
		# PARSE #3:c=390000,e=395172,p=0,cr=630,cu=0,mis=1,r=0,dep=1,og=1,tim=9798661974885
		# EXEC #3:c=10000,e=128,p=0,cr=0,cu=0,mis=0,r=0,dep=1,og=1,tim=9798661975261
		# FETCH #3:c=0,e=263,p=0,cr=0,cu=0,mis=0,r=1,dep=1,og=1,tim=9798661975793
		# STAT #51 id=1 cnt=2 pid=0 pos=1 obj=18 op='TABLE ACCESS BY INDEX ROWID OBJ$ (cr=6 pr=0 pw=0 time=230 us)'
		# STAT #51 id=2 cnt=2 pid=1 pos=1 obj=37 op='INDEX RANGE SCAN I_OBJ2 (cr=4 pr=0 pw=0 time=150 us)'
		# og: optimizer goal
		# nur CPU (c) bei dep=0 aufsummieren, damit kein doppeltes Zählen passiert?
		# Millsap: c values at non-zero recursive depths are rolled up into the statistics 
		# for their recursive parents.
		
		# PARSING IN CURSOR format identical in 9i and 10g
		# 10g example: PARSING IN CURSOR #7 len=41 dep=0 uid=34 oct=3 lid=34 tim=1157853635842194 hv=2469908540 ad='2f05f324'
		# 9i example: PARSING IN CURSOR #1 len=68 dep=0 uid=30 oct=42 lid=30 tim=33754136895 hv=2212335334 ad='7ab276f0'
		# ends with 'END OF STMT' on separate line
		# better to use hash_value or address? hash_value, address is ephemeral, hash
		# value remains constant across instance restarts

=pod

Running the same statement with different optimizer settings or optimizer modes gives multiple entries in v$sql,
but hash_value and address are constant:
select hash_value,address, optimizer_mode, optimizer_env_hash_value from v$sql where sql_text='select 1 from dual';
HASH_VALUE ADDRESS  OPTIMIZER_ OPTIMIZER_ENV_HASH_VALUE
---------- -------- ---------- ------------------------
2866845384 2C990400 FIRST_ROWS               3223272689
2866845384 2C990400 ALL_ROWS                 1209944977
2866845384 2C990400 ALL_ROWS                 3201715534

So it's ok to use hash_value for accounting cost

=cut

		elsif (/^PARSING IN CURSOR #(\d+) len=\d+ dep=(\d+) uid=(\d+) oct=(\d+) lid=(\d+) tim=(\d+) hv=(\d+) ad='([^']*)'/) {
			$cursor_nr=$1;
			$dep=$2;
			$user_id=$3;
			$ora_cmd_type=$4;
			$perm_user_id=$5;
			$tim=$6;
			$hash_value=$7;
			$address=$8;

			if ($db_major_rel >= 11) {
				# 11g PARSING IN CURSOR example:
				# PARSING IN CURSOR #3 len=116 dep=0 uid=32 oct=2 lid=32 tim=15545747608 hv=1256130531 ad='6ab5ff8c' sqlid='b85s0yd5dy1z3'
				if (/.* sqlid='([^']*)'/) {
					$sqlid=$1;
				}
			}

			if ( $debug_level >= 1) {
				printf("Found PARSING IN CURSOR: cursor_nr=%d dep=%d user_id=%d ora_cmd_type=%d perm_user_id=%d tim=%s hash_value=%s address='%s'\n", $cursor_nr, $dep, $user_id, $ora_cmd_type, $perm_user_id, $tim, $hash_value, $address);
				printf("sqlid='%s'\n", $sqlid);
			}
			$stmt_text="";
			for ($line=<INPUT_FILE>; substr($line,0,11) ne 'END OF STMT'; $line=<INPUT_FILE>) {
				$stmt_text .= $line;
			}
			# use constant?
			if ( defined $stmt_list{$hash_value} ) {
				# same statement may be reparsed under a different cursor number
				# mapping from cursor number to hash value may change!
				# must update mapping from cursor number to hash value
				$cursor_to_hv{$cursor_nr}=$hash_value;
				if ( $debug_level > 0) {
					printf("Line %d: known stmt cursor %d, hash value %s\n", $., $cursor_nr, $hash_value);
				}
			}
			else {
				# mapping from cursor number to hash value
				$cursor_to_hv{$cursor_nr}=$hash_value;
				# call init_stmt_record to init record for statement, returns hash ref
				my $cur_stmt=init_stmt_record();
				$cur_stmt->{TEXT}=$stmt_text;
				$cur_stmt->{SQL_ID}=$sqlid;
				$cur_stmt->{MODULE}=$curr_app_mod;
				$cur_stmt->{ACTION}=$curr_app_act;
				$cur_stmt->{DEP}=$dep; # save dependency level
				# add to statement list
				$stmt_list{$hash_value}=$cur_stmt;
				if ( $debug_level && 1) {
					printf("Line: %d new stmt: cursor %d,  hash value %s\n", $., $cursor_nr, $hash_value);
					printf("Variable stmt_text\n'%s'\n", $stmt_text);
					printf("Text in record\n'%s'\n", $cur_stmt->{TEXT});
				}
			}
		}
			# example STAT entries 9i:
			# STAT #4 id=1 cnt=2 pid=0 pos=1 obj=75 op='TABLE ACCESS BY INDEX ROWID IDL_SB4$ '
			# STAT #4 id=2 cnt=2 pid=1 pos=1 obj=123 op='INDEX RANGE SCAN I_IDL_SB41 '
			# 10g
			# STAT #2 id=1 cnt=1 pid=0 pos=1 obj=0 op='SORT AGGREGATE (cr=7 pr=6 pw=0 time=69396 us)'
			# STAT #2 id=2 cnt=441 pid=1 pos=1 obj=12996 op='TABLE ACCESS FULL POEM (cr=7 pr=6 pw=0 time=72275 us)'
			#
			# PARSING IN CURSOR #14 len=175 dep=1 uid=0 oct=3 lid=0 tim=33758635101 hv=3073477137 ad='7a973018'
			# 
			# select u.name,o.name, t.update$, t.insert$, t.delete$, t.enabled
			# from
			# obj$ o,user$ u,trigger$ t  where t.baseobject=:1 and t.obj#=o.obj# and
			# o.owner#=u.user#  order by o.obj#
			# STAT #14 id=1 cnt=0 pid=0 pos=1 obj=0 op='SORT ORDER BY '
			# STAT #14 id=2 cnt=0 pid=1 pos=1 obj=0 op='NESTED LOOPS  '
			# STAT #14 id=3 cnt=0 pid=2 pos=1 obj=0 op='NESTED LOOPS  '
			# STAT #14 id=4 cnt=0 pid=3 pos=1 obj=82 op='TABLE ACCESS BY INDEX ROWID TRIGGER$ '
			# STAT #14 id=5 cnt=0 pid=4 pos=1 obj=130 op='INDEX RANGE SCAN I_TRIGGER1 '
			# STAT #14 id=6 cnt=0 pid=3 pos=2 obj=18 op='TABLE ACCESS BY INDEX ROWID OBJ$ '
			# STAT #14 id=7 cnt=0 pid=6 pos=1 obj=36 op='INDEX UNIQUE SCAN I_OBJ1 '
			# STAT #14 id=8 cnt=0 pid=2 pos=2 obj=22 op='TABLE ACCESS CLUSTER USER$ '
			# STAT #14 id=9 cnt=0 pid=8 pos=1 obj=11 op='INDEX UNIQUE SCAN I_USER# '
			# 
			# indentation
			# Rows     Row Source Operation
			# -------  ---------------------------------------------------
      			# 0  SORT ORDER BY
      			# 0   NESTED LOOPS
      			# 0    NESTED LOOPS
      			# 0     TABLE ACCESS BY INDEX ROWID TRIGGER$
      			# 0      INDEX RANGE SCAN I_TRIGGER1 (object id 130)
      			# 0     TABLE ACCESS BY INDEX ROWID OBJ$
      			# 0      INDEX UNIQUE SCAN I_OBJ1 (object id 36)
      			# 0    TABLE ACCESS CLUSTER USER$
      			# 0     INDEX UNIQUE SCAN I_USER# (object id 11)
			# the plan for a statement with the same hash value may be present several times
			# the code will use the last plan found

			# while testing I encountered an ORACLE V9.2.0.6.0 trace file, where the first line
			# of the plan did not start with id=1:
			# FETCH #1:c=430620,e=1012685,p=297,cr=42816,cu=0,mis=0,r=6,dep=0,og=1,tim=9932687392
			# WAIT #1: nam='SQL*Net message from client' ela= 26143 p1=1413697536 p2=1 p3=0
			# STAT #1 id=8 cnt=6 pid=0 pos=1 obj=0 op='FILTER  '
			# STAT #1 id=9 cnt=2166 pid=8 pos=1 obj=0 op='NESTED LOOPS OUTER '
			# STAT #1 id=10 cnt=2166 pid=9 pos=1 obj=0 op='NESTED LOOPS  '
			# I consider this a bug but indentation works in spite of this
			# Such plans may be concatenated if present multiple times, 
			# since the plan is overwritten when id=1 # is seen.
			# will be noticeable due to repeating id nummbers

			# stat lines end with a line of equal signs like this:
			# =====================

		elsif (/^STAT #(\d+) id=(\d+) cnt=(\d+) pid=(\d+) pos=(\d+) obj=(\d+) op='([^']*)'/) {
			if ( $debug_level > 0) {
				printf("Line %d: %s", $., $_);
			}
			$cursor_nr=$1;
			# should write a sub for this
			if ( ! defined $cursor_to_hv{$cursor_nr} ) {
				printf(STDERR "Warning: STAT entry for cursor %d without prior PARSING IN CURSOR #%d at trace file line %d - execution plan ignored\n", $cursor_nr, $cursor_nr, $.);
			} else {
				$hash_value=$cursor_to_hv{$cursor_nr};
				if ( ! defined $stmt_list{$hash_value} ) {
					printf(STDERR "Internal error assigning execution plan for cursor %s at trace file line %d to statement with hash value %s\n", $cursor_nr, $., $hash_value);
					exit 1;
				}
				$id=$2;
				$cnt=$3;
				$pid=$4;
				$pos=$4;
				$obj_id=$6;
				$row_source=$7;
				if ($obj_id>0) {
					# might collect a list of accessed objects and print table, column
					# and statistics info on these objects at the end of the report
					$obj_info=sprintf(" (object_id=%d)", $obj_id);
				} else {
					$obj_info="";
				}
	
				if ( $id == 1) {
					# first line of execution plan
					$stmt_list{$hash_value}->{STAT}=sprintf("%4d %6d %8d %s %s\n", $id, $pid, $cnt, $row_source, $obj_info);
				} else {
					if ( $debug_level > 0) {
						printf("id '%d' pid '%d' indentation[$pid] '%d' op %s obj_info %s\n", $id, $pid, $indentation[$pid], $row_source, $obj_info);
					}
					# further lines of execution plan
					# indent one level more than parent
					$indentation[$id]=$indentation[$pid]+1;
					$stmt_list{$hash_value}->{STAT}.= sprintf("%4d %6d %8d%s%s%s\n", $id, $pid, $cnt, " " x ($indentation[$id]), $row_source, $obj_info);
				}
				if ( $debug_level > 0) {
					printf("Line %d: plan for cursor %s hash value %s\n", $., $cursor_nr, $hash_value);
				}
			}
		}
		elsif (/^($action) #(\d+):c=(\d+),e=(\d+),p=(\d+),cr=(\d+),cu=(\d+),mis=(\d+),r=(\d+),dep=(\d+),og=(\d+),tim=(\d+)/i) {
			$stmt_type=$1;
			$cursor_nr=$2;
			$cpu=$3;
			$elapsed=$4;
			$disk=$5;
			$cr=$6;
			$cur_read=$7;
			$miss=$8;
			$rows=$9;
			$dep=$10;
			$opt_goal=$11;
			$tim=$12;
			if ( $debug_level > 0) {
				print "$_\n";
				printf("Line %d: stmt_type=%s cursor_nr=%d cpu=%d elapsd=%d disk=%d cr=%d cur_rd=%d mis=%d rows=%d dep=%d og=%d tim=%s\n", $., $stmt_type, $cursor_nr, $cpu, $elapsed, $disk, $cr, $cur_read, $miss, $rows, $dep, $opt_goal, $tim);
			}
			# if dep=0 then do accounting
			if ( $dep == 0 ) {
				# add e value of database call which rolls up waits within the call to response time R
				$R+=$elapsed;
				$physical_reads+=$disk;
				$consistent_gets+=$cr;
				$db_block_gets+=$cur_read;
				$cursor_misses+=$miss;
				$rows_processed+=$rows;
			}
			# check that hash value for cursor is known
			# trace file might start with a cursor # for which
			# no PARSING IN is in the same trace file
			if ( defined $cursor_to_hv{$cursor_nr} ) {
				# per statement accounting for statements sent by client, i.e. dep=0
				# map cursor nr to hash value first
				$hash_value=$cursor_to_hv{$cursor_nr};
				if ( $stmt_type eq "PARSE" ) {
					if ( $dep == 0 ) {
 						# add only at dependency level 0, lower dep levels rolled up
 						$ela_per_action{"parse CPU"}+=$cpu;
 					}
					$stmt_list{$hash_value}->{PARSE_COUNT}+=1;
					$stmt_list{$hash_value}->{PARSE_ELAPSED}+=$elapsed;
					$stmt_list{$hash_value}->{PARSE_CPU}+=$cpu;
					$stmt_list{$hash_value}->{PARSE_DISK}+=$disk;
					$stmt_list{$hash_value}->{PARSE_CR}+=$cr;
					$stmt_list{$hash_value}->{PARSE_CUR_READ}+=$cur_read;
					$stmt_list{$hash_value}->{PARSE_ROWS}+=$rows;
					# optimizer goal might be different for identical statement texts
					if ( $miss == 0 ) {
						$cursor_hits++;
						$stmt_list{$hash_value}->{SOFT_PARSE_COUNT}+=1;
					} else {
						$stmt_list{$hash_value}->{HARD_PARSE_COUNT}+=1;
					}
				} elsif ( $stmt_type eq "EXEC" ) {
					if ( $dep == 0 ) {
 						# add only at dependency level 0, lower dep levels rolled up
 						$ela_per_action{"exec CPU"}+=$cpu;
 					}
					$stmt_list{$hash_value}->{EXEC_COUNT}+=1;
					$stmt_list{$hash_value}->{EXEC_ELAPSED}+=$elapsed;
					$stmt_list{$hash_value}->{EXEC_CPU}+=$cpu;
					$stmt_list{$hash_value}->{EXEC_DISK}+=$disk;
					$stmt_list{$hash_value}->{EXEC_CR}+=$cr;
					$stmt_list{$hash_value}->{EXEC_CUR_READ}+=$cur_read;
					$stmt_list{$hash_value}->{EXEC_ROWS}+=$rows;
				} elsif ( $stmt_type eq "FETCH" ) {
					if ( $dep == 0 ) {
 						# add only at dependency level 0, lower dep levels rolled up
 						$ela_per_action{"fetch CPU"}+=$cpu;
 					}
					$stmt_list{$hash_value}->{FETCH_COUNT}+=1;
					$stmt_list{$hash_value}->{FETCH_ELAPSED}+=$elapsed;
					$stmt_list{$hash_value}->{FETCH_CPU}+=$cpu;
					$stmt_list{$hash_value}->{FETCH_DISK}+=$disk;
					$stmt_list{$hash_value}->{FETCH_CR}+=$cr;
					$stmt_list{$hash_value}->{FETCH_CUR_READ}+=$cur_read;
					$stmt_list{$hash_value}->{FETCH_ROWS}+=$rows;
				}
				# total elapsed time for PARSE, EXEC, FETCH 
				# theoretically should include wait time, but there are traces of LOB operations
				# where direct path read/write and SQL*Net more data from client are not rolled up into e
				$stmt_list{$hash_value}->{TOTAL_E_PARSE_EXEC_FETCH}+=$elapsed;
				# total elapsed time for PARSE, EXEC, FETCH + WAIT used for sorting
				$stmt_list{$hash_value}->{TOTAL_ELAPSED}+=$elapsed;
			} else {
				# in Perl, line number of input file is $.
				printf(STDERR  "Warning: PARSING IN CURSOR for cursor %d missing in trace at line %d\n", $cursor_nr, $.);
			}
			# t0 is first time stamp of any database call
			if ($t0 == 0) {
				$t0=$tim;
			}
			# t1 is last time stamp of any database call
			$t1=$tim;
			# increment occurences of PARSE, EXEC, FETCH
			$occurrences{$stmt_type}++;
		} elsif (/^XCTEND rlbk=(\d+), rd_only=(\d+)/) {
			#printf "Found XCTEND %d %d\n", $1, $2;
			if ( $1 == 0 ) {
				if ( $2 == 0 ) {
					$commit_rw++;
				} else {
					$commit_ro++;
				}
			} else {
				if ( $2 == 0 ) {
					$rollback_rw++;
				} else {
					$rollback_ro++;
				}
			}

=for commentary

		 application instrumentation
		 shared server currently not supported
		 note: shared server does not re-emit MODULE and ACTION when servicing a different session
		 correct detection of module & action would require maintaining a hash of SID.SERIAL# and
		 associated module & action (and possibly service name)

=cut

		} elsif (/^\*\*\* MODULE NAME:\(([^\)]*)\)/) {
			# 10g module examples
			# *** MODULE NAME:(img_load) 2007-11-06 16:05:32.312
			if ($1 eq "") {
				$curr_app_mod="undefined";
			} else {
				$curr_app_mod=$1;
			}
			if ( $debug_level > 0) {
				printf "Found module '%s'; line: %s", $curr_app_mod, $_;
			}
		} elsif (/^\*\*\* ACTION NAME:\(([^\)]*)\)/) {
			# 10g action examples
			# *** ACTION NAME:(read_exif) 2007-11-06 16:05:32.312
			# *** ACTION NAME:() 2007-11-06 16:05:32.296
			if ($1 eq "") {
				$curr_app_act="undefined";
			} else {
				$curr_app_act=$1;
			}
			if ( $debug_level > 0) {
				printf "Found action '%s'; line: %s", $curr_app_act, $_;
			}
		} elsif (/^APPNAME mod='([^')]*)' mh=\d+ act='([^')]*)'/) {
			# 9i module and action examples
			# APPNAME mod='SQL*Plus' mh=3669949024 act='' ah=4029777240
			# APPNAME mod='SQL*Plus' mh=3669949024 act='dequeue' ah=3611575685
			if ($1 eq "") {
				$curr_app_mod="undefined";
			} else {
				$curr_app_mod=$1;
			}
			if ($2 eq "") {
				$curr_app_act="undefined";
			} else {
				$curr_app_act=$2;
			}
			if ( $debug_level > 0) {
				printf "Found module '%s' action '%s'; line: %s", $curr_app_mod, $curr_app_act, $_;
			}
		}
}
if ($sum_ela == 0) {
	printf("Warning: No wait events in trace file. Expect a very inaccurate resource profile! Please use level 8 or level 12 SQL trace\n\n");
}
	close(INPUT_FILE);
	print "Resource Profile\n";
	print "================\n";
	#print keys %ela, "\n";
	# interval between highest tim timestamp and lowest tim timestamp
	my $interval=$t1-$t0;
	# response time R is sum of e values of database calls plus sum of ela values of waits between database calls
	if ( $R > 0 ) {
		# unknown is R - (cpu + sum_ela)
		$ela{"total CPU"}+=$ela_per_action{"parse CPU"} + $ela_per_action{"exec CPU"} + $ela_per_action{"fetch CPU"};
		$occurrences{"total CPU"}=$occurrences{"PARSE"} + $occurrences{"EXEC"} + $occurrences{"FETCH"}; 
		$ela{"unknown"}=$R-($ela{"total CPU"} + $sum_ela);
		# must initialize occurences hash for key unknown
		$occurrences{"unknown"}="";
		printf "\nResponse time: %.3fs; max(tim)-min(tim): %.3fs\n", $R/$unit, $interval/$unit;
		printf "Total wait time: %.3fs\n", $sum_ela/$unit;
		printf "----------------------------\n\n";
		#printf "t0: $t0 t1: $t1\n";
		printf "Note: 'SQL*Net message from client' waits for more than %.3fs are considered think time\n", $think_time_threshold;
		printf "Wait events and CPU usage:\n";
		printf "%9s %7s %12s %10s %-35s\n", "Duration", "Pct", "Count", "Average", "Wait Event/CPU Usage/Think Time";
		printf "%9s %7s %12s %10s %-35s\n", "-"x8, "-"x6, "-"x12, "-"x10, "-"x35;
		# output results sorted by time
		printf "%8.3fs %6.2f%% %12s %10s %-35s\n", $ela{$_}/$unit, $ela{$_}/$R*100, $occurrences{$_}, ($_ eq "unknown") ? "" : sprintf("%3.6fs", ($ela{$_}/$unit)/$occurrences{$_}), $_ for sort { $ela{$b} <=> $ela{$a} } keys %ela;
		printf "%8s- %5s- %-35s\n", "-"x8, "-"x6, "-"x59;
		printf "%8.3fs %5.2f%% %-55s\n", $R/$unit, 100, "Total response time";

		printf "\nTotal number of roundtrips (SQL*Net message from/to client): %d\n", $occurrences{"SQL*Net message from client"} + $occurrences{"think time"};
		
		printf "\nCPU usage breakdown\n------------------------\n";
	printf "parse CPU: %8.2fs (%d PARSE calls)\n", $ela_per_action{"parse CPU"}/$unit, $occurrences{"PARSE"};
	printf "exec  CPU: %8.2fs (%d EXEC calls)\n", $ela_per_action{"exec CPU"}/$unit, $occurrences{"EXEC"};
	printf "fetch CPU: %8.2fs (%d FETCH calls)\n", $ela_per_action{"fetch CPU"}/$unit, $occurrences{"FETCH"};

	# application instrumentation
	#printf "%8.3fs %-35s\n", $ela_per_app_mod{$_}/$unit, $_ for sort { $ela_per_app_mod{$b} <=> $ela_per_app_mod{$a} } keys %ela_per_app_mod;
	
	printf "\nStatistics:\n";
	printf "-----------\n";
	printf "COMMITs (read write): %d -> transactions/sec %.3f\n", $commit_rw, $commit_rw/($R/$unit);
	printf "COMMITs (read only): $commit_ro\n";
	printf "ROLLBACKs (read write): $rollback_rw\n";
	printf "ROLLBACKs (read only): $rollback_ro\n";
	printf "rows processed: $rows_processed\n";
	printf "cursor hits (soft parses): $cursor_hits\n";
	printf "cursor misses (hard parses): $cursor_misses\n";
	printf "consistent gets: $consistent_gets\n";
	printf "db block gets: $db_block_gets\n";
	printf "physical reads: $physical_reads\n";
	printf("buffer cache hit ratio: ");
	if ( $db_block_gets+$consistent_gets > 0) {
		printf("%.2f%%\n", (1-($physical_reads / ($db_block_gets+$consistent_gets)))*100);
	} else {
		printf("n/a (both db block gets and consistent gets are 0 - cannot divide by 0)\n");
	}

	printf "\nPhysical read breakdown:\n------------------------\n";
	printf "single block: %d\n", $physical_reads{sequential};
	printf "multi-block: %d\n", $physical_reads{scattered};

	printf "\nLatch wait breakdown\n------------------------\n";
	if ($db_major_rel == 9) {
		foreach my $latch_nr (keys %latch_free_waits) {
			printf "%-30s waits: %4d sleeps: %4d\n", $latch_name_9i{$latch_nr}, $latch_free_waits{$latch_nr}, $latch_sleeps{$latch_nr};
		}
	} elsif ($db_version eq "10.1" ) {
		foreach my $latch_nr (keys %latch_free_waits) {
			printf "%-30s waits: %4d sleeps: %4d\n", $latch_name_10gR1{$latch_nr}, $latch_free_waits{$latch_nr}, $latch_sleeps{$latch_nr};
		}
	} elsif ($db_version eq "10.2" ) {
		foreach my $latch_nr (keys %latch_free_waits) {
			printf "%-30s waits: %4d sleeps: %4d\n", $latch_name_10gR2{$latch_nr}, $latch_free_waits{$latch_nr}, $latch_sleeps{$latch_nr};
		}
	} elsif ($db_version eq "11.1" ) {
		foreach my $latch_nr (keys %latch_free_waits) {
			printf "%-30s waits: %4d sleeps: %4d\n", $latch_name_11gR1{$latch_nr}, $latch_free_waits{$latch_nr}, $latch_sleeps{$latch_nr};
		}
	} else {
		printf(STDERR "Warning: latch number to latch name mapping for release $db_version not implemented\n");
	}
	printf "\nEnqueue wait breakdown (enqueue name, lock mode)\n";
	printf "------------------------------------------------\n";
	foreach my $enqueue_name (keys %enqueue_waits) {
		printf "%-5s wait time: %8.3fs waits: %10d\n", $enqueue_name, $enqueue_wait_time{$enqueue_name}/$unit, $enqueue_waits{$enqueue_name};
	}
	print "\nStatements Sorted by Elapsed Time (including recursive resource utilization)\n";
	print "==============================================================================\n";
	# sorting: print out statements sorted by total elapsed time
	 per_stmt_results($_, $unit) for sort { $stmt_list{$b}->{TOTAL_ELAPSED} <=> $stmt_list{$a}->{TOTAL_ELAPSED} } keys %stmt_list;
} else {
	print "Could not determine response time. Please check contents of trace file\n";
	exit 1;
}
