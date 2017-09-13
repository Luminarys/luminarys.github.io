% writing a bittorrent client
%
%

I've been unhappy with the state of bittorrent clients for some time now.
Every client I've used has been some combination of glitchy, unintuitive, slow,
or hard to setup. Almost all have RPC protocols which are poorly documented, hard to use, or both.
It's a fairly frustrating state which I'm trying to remedy (for myself at least).

For the past 9 months I've been working on a bittorrent client, [synapse](https://synapse-bt.org).
Working off of public documentation and other client source code/behavior, synapse has become
a fairly usable, though still WIP, client. In the process I've learned a few things which might
be of interest to others who want to implement a client themselves, or just want to know more about
how clients work. This is only a small portion of the various challenges associated with
building a bittorrent client and I strongly recommend reading the libtorrent blog[^1] if
you'd like to learn more.

### queuing
Most information on the web about request queuing is either wrong, or ambiguous.
This is largely because the documents were written 10+ years ago when the average
household internet connection was orders of magnitude less than it is now.
As the theory page[^2] notes, queuing is likely the most important aspect of
network performance. Keeping a request queue of 5 pieces is a bad idea
for most connections these days. To illustrate, on a 20 Mbps connection,
downloading from a client with 40 ms RTT, this will likely happen:

* The client will start by requesting 5 blocks[^3]. These will be batched into a single TCP packet and sent.
* 20 ms later the seeder receives the request. Assuming it can instantly read the 80 KiB from disk,
the blocks are then sent back.
* Another 20 ms later, the client begins receiving the blocks. As it recieves each block, it requests
a new block to keep the pipeline at 5 requests.
* Because the 5 blocks are likely received in quick succession,
5 responses will likely be sent again in a batch.
* This process repeats, with 80 KiB of data transferred every 40 ms.

You can see that even in this rather optimistic scenario, the client's connection is far from being
used optimally. In fact, it's an order of magnitude less than what it could be, around 2 MiB/s.

To make full use of a seeder's connection, adaptive queuing has to be used.
The general idea behind this is to gradually increase the number of requests
queued for a peer until the download speed is saturated, or the peer
can no longer fulfill all the requests in a timely rate.
Many clients keep pipelines of hundreds of requests in order to make full use
of the connection, and synapse is no exception.

For instance, rtorrent makes use of this algorithm when aggresively requesting pieces:
```C++
if (rate < 20)
    return rate + 2;
else
    return rate / 5 + 18;
```
where rate is the peer's download rate in KiB/s, and the return value
is the number of requests to keep in the peer's queue.
This sort of adaptive queuing makes the best use of the connection
and means that fewer peers are needed to maximize download speeds.

### threading
As far as I know, most popular bittorrent clients and libraries use a small number
of threads. This is for a good reason. Bittorrent clients require lots of shared state
between each peer connection to do things like requesting new pieces and recording
downloaded ones. An approach of many threads with locks around state is
both inefficient and error prone[^4].

A better approach is to use non blocking connections with appropriate parsers.
All connections are managed on a single thread or split across a few as needed.
Peer messages can then be processed as event streams, with responses also queued as needed.
State management like this is simple and the client fairly performant.

This does leave the question of how disk IO is done, since the main thread has
to be non blocking. Clients handle this in a variety of ways. Synapse utilizes
a thread which handles disk jobs, performing reads/writes as well as other
filesystem related tasks. Other clients use threadpools or mmap based approaches.

### piece picking
Arvid Norberg's post on rarest first piece picking[^5] is an excellent overview
of the process, but there are a few points worth touching on.

When a piece is succesfully picked, removing it from the picker is fairly
expensive and complicated, as every single piece in the ordered list of piece
might need to be shifted forward, with all appropriate boundaries and indeces
updated. Synapse mitigates this by attaching a flag to each piece which marks
it as completed and on completion increments its availability by a large number,
shifting it to the end of the vector. This may sound expensive, but it's actually
not. Priority levels tend not to be more than 10-20 for most torrents,
meaning only a few actual swap operations need to be performed to shift the
piece to the back of the vector. This has the additional advantage of
making it very easy to "unpick" a piece, which may happen if the piece is invalidated,
since it just has to have availability decremented by an equal amount. If it was
removed, the entire picker would have to be rebuilt to get the previous priority.

Another change synapse has made is the separation of piece picking and block picking.
The picker in synapse works by specifying the best piece to download from a peer
rather than recording the actual blocks picked themselves. A block picker then picks
an appropriate block for the peer. This separation of concerns simplifies picker
code and makes it easier to test, but also has some significant advantages.
For example, when a user swaps pickers or updates a file priority, the
new picker can be rebuilt from scratch while maintaining the current state
of downloading blocks independently.


[^1]: <http://blog.libtorrent.org/>
[^2]: <https://wiki.theory.org/index.php/BitTorrentSpecification#Algorithms>
[^3]: The bittorrent protocol transfers data between clients in "blocks",
    which consist of a piece index, offset in the piece, and 16 KiB of data.
[^4]: <https://monotorrent.blogspot.com/2008/10/monotorrent-050-good-bad-and-seriously.html>
[^5]: <http://blog.libtorrent.org/2011/11/writing-a-fast-piece-picker>
