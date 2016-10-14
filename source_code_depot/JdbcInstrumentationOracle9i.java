/* $Header: /cygdrive/c/home/ndebes/it/java/RCS/JdbcInstrumentationOracle9i.java,v 1.2 2007/09/10 14:44:56 ndebes Exp ndebes $
put this code into file JdbcTest.java
jdbc thin UNIX, Oracle10g:
export CLASSPATH=$ORACLE_HOME/jdbc/lib/ojdbc14.zip:.
javac JdbcInstrumentationOracle9i.java
java JdbcInstrumentationOracle9i
jdbc oci:
requires $ORACLE_HOME/lib/libocijdbc9.so and LD_LIBRARY_PATH=$ORACLE_HOME/lib (lib32 on 64-bit ORACLE installations)

Example Run with JDBC OCI
===========
$ echo $CLASSPATH
/applications/oracle/9.2.0.7/jdbc/lib/ojdbc14.jar:.
$ echo $LD_LIBRARY_PATH
/applications/oracle/9.2.0.7/lib32


JDBC driver version: 9.2.0.7.0

Defaults (and Properties for JDBC Thin only):

AUDSID: 20
CLIENT_IDENTIFIER: null
CLIENT_INFO: null
HOST: dbserver1
OSUSER: oracle
TERMINAL: pts/11

Please query V$SESSION and hit return to continue when done.

In another window:
set null <NULL>
col program format a27
col module format a14 word_wrapped
col action format a8
col client_identifier format a18
SELECT program, module, action, client_identifier FROM v$session WHERE audsid=20;

PROGRAM                    MODULE         ACTION   CLIENT_IDENTIFIER
-------------------------- -------------- -------- ------------------
java@dbserver1 (TNS V1-V3) java@dbserver1 <NULL>   <NULL>
                           (TNS V1-V3)

continue:
Today is September 10. 2007

End To End Metrics:

CLIENT_IDENTIFIER: 20
CLIENT_INFO: Instrumentation compatible with Oracle9i JDBC driver

Please query V$SESSION again and hit return to continue when done.

SQL> SELECT program, module, action, client_identifier FROM v$session WHERE audsid=20;

PROGRAM                    MODULE         ACTION   CLIENT_IDENTIFIER
-------------------------- -------------- -------- ------------------
java@dbserver1 (TNS V1-V3) app_mod        app_act  20


with Oracle9i JDBC driver, get this in trace file:
*** SESSION ID:(20.6794) 2007-10-9 16:21:08.294
APPNAME mod='java@<client host name> (TNS V1-V3)' mh=0 act='' ah=0

after calling dbms_application_info:
APPNAME mod='app_mod' mh=299142939 act='app_act' ah=623083497

Note: client identifer not written to SQL trace file by Oracle9i


Example Run with JDBC Thin
==========================
SQL> SELECT program, module, action, client_identifier FROM v$session WHERE audsid=22

PROGRAM                     MODULE         ACTION   CLIENT_IDENTIFIER
--------------------------- -------------- -------- ------------------
JdbcInstrumentationOracle9i JdbcInstrument <NULL>   <NULL>
                            ationOracle9i

SQL> SELECT program, module, action, client_identifier FROM v$session WHERE audsid=22

PROGRAM                     MODULE         ACTION   CLIENT_IDENTIFIER
--------------------------- -------------- -------- ------------------
JdbcInstrumentationOracle9i app_mod        app_act  22



*/
import java.io.IOException;
import java.sql.*;
import java.io.*;
import oracle.jdbc.OracleConnection;

class JdbcInstrumentationOracle9i {
	public static void main (String args[]) throws SQLException {
		byte buffer[]=new byte[80];
		String audsid="";

		try {
			// Load Oracle driver
			DriverManager.registerDriver (new oracle.jdbc.OracleDriver());

			java.util.Properties prop = new java.util.Properties();
			// properties are evaluated once when the session is created. Not suitable for setting the program or other information after getConnection has been called
			prop.put("user","ndebes");
			prop.put("password","secret");
			prop.put("v$session.machine","p_machine"); // works with JDBC Thin only
			prop.put("v$session.client_info","cli_inf"); // works with 9.2.0.8 JDBC Thin only, no effect in JDBC 10.2.0.3
			prop.put("v$session.osuser","p_osuser"); // works with JDBC Thin only
			prop.put("v$session.terminal","pts/1"); // works with JDBC Thin only
			prop.put("v$session.program","JdbcInstrumentationOracle9i"); // works with JDBC Thin only, if set in 10.2.0.3 set as program and module, as expected end to end metrics overwrite module, program is not overwritten
			prop.put("v$session.module","p_mod"); // no effect
			prop.put("v$session.action","p_act"); // no effect
			prop.put("v$session.client_identifier","p_client"); // no effect
			Connection conn = DriverManager.getConnection("jdbc:oracle:oci:@teng.oradbpro.com",prop);
			//Connection conn = DriverManager.getConnection("jdbc:oracle:thin:@(DESCRIPTION=(ADDRESS=(PROTOCOL=TCP)(HOST=localhost)(PORT=1521))(CONNECT_DATA=(SERVICE_NAME=orcl.oradbpro.com)))",prop);

			// Create Oracle DatabaseMetaData object
			DatabaseMetaData meta = conn.getMetaData();
			// gets driver info:
			System.out.println("JDBC driver version: " + meta.getDriverVersion() + "\n");
			
			PreparedStatement alterstmt =conn.prepareStatement("ALTER SESSION SET EVENTS '10046 trace name context forever, level 12'");
			alterstmt.execute();
			alterstmt.close();


			// program not available with sys_context
			Statement stmt = conn.createStatement ();
			String sys_context_stmt="SELECT " +
				"sys_context('userenv', 'sessionid')," +
				"sys_context('userenv', 'client_identifier')," +
				"sys_context('userenv', 'client_info')," +
				"sys_context('userenv', 'host'), /* corresponds to v$session.machine */" +
				"sys_context('userenv', 'os_user'), /* corresponds to v$session.osuser */" +
				"sys_context('userenv', 'terminal')" +
				"FROM dual";
			ResultSet rset = stmt.executeQuery(sys_context_stmt);

			System.out.println("Defaults (and Properties for JDBC Thin only):\n");
			while (rset.next ()) {
				audsid=rset.getString (1);
				System.out.println ("AUDSID: " + audsid);
				System.out.println ("CLIENT_IDENTIFIER: " + rset.getString (2));
				System.out.println ("CLIENT_INFO: " + rset.getString (3));
				System.out.println ("HOST: " + rset.getString (4));
				System.out.println ("OSUSER: " + rset.getString (5));
				System.out.println ("TERMINAL: " + rset.getString (6));
			}
			//close the result set
			rset.close();
	
			System.out.println("\nPlease query V$SESSION and hit return to continue when done.\n");
			System.in.read(buffer, 0, 80); // => This line is just to stop until you press enter. 
			CallableStatement app_context = conn.prepareCall("begin \n" +
				"dbms_application_info.set_module(?, ?);\n" +
				"dbms_application_info.set_client_info(?);\n" +
				"dbms_session.set_identifier(?);\n" +
				"end;");
			app_context.setString(1, "app_mod");
			app_context.setString(2, "app_act");
			app_context.setString(3, "Instrumentation compatible with Oracle9i JDBC driver");
			app_context.setString(4, audsid);
			/*
	 		* crashes with JDBC OCI when the two lines below are uncommented:
	 		* EXCEPTION_ACCESS_VIOLATION (0xc0000005) at pc=0x61d32910, pid=4816, tid=4400
			*/
			app_context.execute();
	
			stmt = conn.createStatement ();
			rset = stmt.executeQuery ("SELECT to_char(sysdate, 'Month dd. yyyy') FROM dual");
			while (rset.next ())
			System.out.println ("Today is " + rset.getString (1));
			//close the result set, statement, and the connection
			rset.close();

			rset = stmt.executeQuery(sys_context_stmt);
			System.out.println("\nEnd To End Metrics:\n");
			while (rset.next ()) {
				System.out.println ("CLIENT_IDENTIFIER: " + rset.getString (2));
				System.out.println ("CLIENT_INFO: " + rset.getString (3));
			}
			stmt.close();

			System.out.println("\nPlease query V$SESSION again and hit return to continue when done.\n");
			// Pause until user hits enter
			System.in.read(buffer, 0, 80); 
	
			app_context.setString(1, "");
			app_context.setString(2, "");
			app_context.setString(3, "");
			app_context.setString(4, "");
			/*
	 		* crashes with JDBC OCI when the two lines below are uncommented:
	 		* EXCEPTION_ACCESS_VIOLATION (0xc0000005) at pc=0x61d32910, pid=4816, tid=4400
			*/
			app_context.execute();
			app_context.close();
			conn.close();
		}
		catch (SQLException e)
		{
			e.printStackTrace();
		}
		catch (IOException ioe)
		{
			ioe.printStackTrace();
		}
	}
}
