event=10000
counter=0
while [ $event -lt 11000 ]
do
        text=`oerr ora $event`
        if [ "$text" != "" ]; then
                counter=`expr $counter + 1`
                echo "$text"
        fi
        event=`expr $event + 1`
done
echo "$counter events found."
