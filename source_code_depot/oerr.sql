variable msg varchar2(4000)
set autoprint on
begin
	:msg:=sqlerrm(-&error_code);
end;
/
