VARIABLE loc VARCHAR2(30)
EXEC :loc:='South San Francisco'
ALTER SESSION SET EVENTS '10053 trace name context forever, level 1';

SELECT emp.last_name, emp.first_name, j.job_title, d.department_name, l.city, 
	l.state_province, l.postal_code, l.street_address, emp.email, 
	emp.phone_number, emp.hire_date, emp.salary, mgr.last_name
FROM hr.employees emp, hr.employees mgr, hr.departments d, hr.locations l, hr.jobs j
WHERE l.city=:loc
AND emp.manager_id=mgr.employee_id
AND emp.department_id=d.department_id
AND d.location_id=l.location_id
AND emp.job_id=j.job_id;
ALTER SESSION SET EVENTS '10053 trace name context off';
