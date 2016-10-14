/* $Header: /cygdrive/c/home/ndebes/it/java/RCS/ApplicationInstrumentation.java,v 1.2 2007/10/31 14:57:55 ndebes Exp ndebes $
Note: Oracle10g ORACLE_HOME includes a JDK (undocumented). Java compiler is $ORACLE_HOME/jdk/bin/javac(.exe). Put $ORACLE_HOME/jdk/bin into PATH to use this compiler.
put this code into file ApplicationInstrumentation.java
jdbc thin UNIX, Oracle10g:
export CLASSPATH=$ORACLE_HOME/jdbc/lib/ojdbc14.zip:.
javac JdbcTest.java
java JdbcTest
JDBC OCI:
requires $ORACLE_HOME/lib/libocijdbc9.so and LD_LIBRARY_PATH=$ORACLE_HOME/lib

Windows (example settings for Oracle9i):
Note: jar file name for JDK 1.4 is identical in 9i and 10g, but the driver version is different.
set CLASSPATH=c:\oracle\product\db9.2\jdbc\lib\ojdbc14.jar;.
set PATH=C:\oracle\product\db9.2\bin;c:\programme\oracle\product\db10.2\jdk\bin
JDBC OCI DLL ocijdbc9.dll is located through PATH

set CLASSPATH=%ORACLE_HOME%\jdbc\lib\ojdbc14.jar;.
set PATH=%PATH%;%ORACLE_HOME%\jdk\bin

SELECT service_name, module, action, client_identifier, machine, osuser, terminal, program 
FROM v$session 
WHERE module='ApplicationInstrumentation';

SELECT service_name, module, action, client_identifier, machine, osuser, terminal, program FROM v$session WHERE sid=144

examples of JDBC URLs:
jdbc:oracle:thin:@//dbserver:1521/TEN.oradbpro.com
                    ^^^^     ^^^^ ^^^^
		    host     port instance service (lsnrctl services)
jdbc:oracle:oci:@ten_rac.oradbpro.com
                 ^^^^^^^^^^^^^
		 Net service name (tnsnames.ora)

Undocumented Aspects
====================
- service name, module, action and client identifier as arguments to DBMS_MONITOR are case sensitive
- service name, module, action and client identifier as arguments to TRCSESS are case sensitive
- what kind of trace file entries are emitted by JDBC end to end metrics
- that drill down with TRCSESS is not possible (e.g. service to module)
- that TRCSESS does not work in shared server environments under certain conditions
- whether compatibility of TRCSESS with trace files from Oracle9i and previous releases exists
- that trace file entries created with JDBC end to end metrics which cause tracing through DBMS_MONITOR to be switched off are not written
- at what time application instrumentation entries are written. Not written again, when shared server services another session
- module, action and client identifier are written each time SQL trace is enabled in a dedicated server. This is important to ensure TRCSESS works in a connection pooling environment
- which columns in V$SESSION are set with JDBC end to end metrics
*/
import java.io.IOException;
import java.sql.*;
import java.io.*;
import oracle.jdbc.OracleConnection;

class ApplicationInstrumentation {
	public static void main(String args[]) throws SQLException {
		if (args.length != 3) {
			System.out.println("Usage: java ApplicationInstrumentation username password JDBC_URL\n");
		}
		else {
			ApplicationInstrumentation appinstr= new ApplicationInstrumentation(args[0], args[1], args[2]);
		}
	}
	public ApplicationInstrumentation(String username, String pwd, String url) {
		byte buffer[]=new byte[80];
		try {
			DriverManager.registerDriver(new oracle.jdbc.OracleDriver());
			java.util.Properties prop = new java.util.Properties();
			// properties are evaluated once by JDBC Thin when the session is created. Not suitable for setting the program or other information after getConnection has been called
			prop.put("user", username);
			prop.put("password", pwd);
			prop.put("v$session.program", getClass().getName()); // works with JDBC Thin only; if specified, then set as program and module, as expected end to end metrics overwrites the module; program is not overwritten
			//Connection conn = DriverManager.getConnection(url, prop);
			Connection conn = DriverManager.getConnection(url, prop);
			conn.setAutoCommit(false);
			// Create Oracle DatabaseMetaData object
			DatabaseMetaData metadata = conn.getMetaData();
			// gets driver info:
			System.out.println("JDBC driver version: " + metadata.getDriverVersion() + "\n");

			System.out.println("\nPlease query V$SESSION and hit return to continue when done.\n");
			System.in.read(buffer, 0, 80); // Pause until user hits enter

			// end to end metrics interface
			String app_instrumentation[] = new String[OracleConnection.END_TO_END_STATE_INDEX_MAX];
			app_instrumentation[OracleConnection.END_TO_END_CLIENTID_INDEX]="Ray.Deevers";
			app_instrumentation[OracleConnection.END_TO_END_MODULE_INDEX]="mod";
			app_instrumentation[OracleConnection.END_TO_END_ACTION_INDEX]="act";
			((OracleConnection)conn).setEndToEndMetrics(app_instrumentation,(short)0);
			Statement stmt = conn.createStatement();
			ResultSet rset = stmt.executeQuery("SELECT userenv('sid'), to_char(sysdate, 'Month dd. yyyy hh24:mi') FROM dual");
			while (rset.next())
				System.out.println("This is session " + rset.getString(1) + " on " + rset.getString(2));
			rset.close();
			System.out.println("\nPlease query V$SESSION and hit return to continue when done.\n");
			System.in.read(buffer, 0, 80); // Pause until user hits enter
			// with connection pooling, execute this code before returning session to connection pool
			app_instrumentation[OracleConnection.END_TO_END_CLIENTID_INDEX]="";
			app_instrumentation[OracleConnection.END_TO_END_MODULE_INDEX]="";
			app_instrumentation[OracleConnection.END_TO_END_ACTION_INDEX]="";
			((OracleConnection)conn).setEndToEndMetrics(app_instrumentation,(short)0);
			rset = stmt.executeQuery("SELECT 'application instrumentation settings removed' FROM dual");
			while (rset.next())
				System.out.println(rset.getString(1));
			rset.close();
			System.out.println("\nPlease query V$SESSION and hit return to continue when done.\n");
			System.in.read(buffer, 0, 80); // Pause until user hits enter
			conn.close();
		}
		catch(SQLException e)
		{
			e.printStackTrace();
		}
		catch(IOException ioe)
		{
			ioe.printStackTrace();
		}
	}
}
