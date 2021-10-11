# gridbot
Your grid management bot with the lot.

## About
This code has existed in one form or another for the last 10 years or more.
It started out as a simple way to issue commands to start and stop guests in the grid, and has grown to include status capture and even a crude IPC mechanism.
Current status is a bit shaky.

### What's the grid?
Also known as the "Large Scale Cloning Experiment", the grid is an experiment into using z/VM techniques to push boundaries of scalability of Linux instances on IBM Z/LinuxONE.
The first "version" of the grid ran 200 Linux guests in 16GB of memory (technically 18GB since 2GB of expanded storage was used for first-level paging at the time).
At its operational peak, the grid ran over 4000 active Linux virtual machines in that same 16GB of memory.

### What's z/VM?
IBM's premier enterprise-grade hypervisor for the IBM Z and LinuxONE platforms.
The history of z/VM dates back to VM/370, first released in August 1972 (the informal history of z/VM dates back even further, to the early 1960s with CP-40, and 1967's CP-67 for the IBM 360/67).

## Watch this space
More details to come.
