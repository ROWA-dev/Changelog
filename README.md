# More Balancing and Cleanup
Update 1.4.4

smash got a lil rework
fixed up the true stun on things..
EVERY feintwait aka windup call site value has been changed BUT the timings are actually the same... why?
removed the magic - 0.08 from feintwait function... it was an artifact for bots reading attackat so they could parry attacks 0.08 earlier
all the callsites values are accounted for that one change.
for the sake of future code and windup accuracy

dodgeH value actually works now

and alot more