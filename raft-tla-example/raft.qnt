// -*- mode: Bluespec; -*-
/// Raft consensus algorithm specification.
/// Translated from the TLA+ specification by Diego Ongaro (2014).
///
/// Key differences from TLA+:
///   - Messages modeled as Set (not bag) — no duplicate messages
///   - Lists are 0-indexed; protocol indices remain 1-based
///   - History variables (elections, allLogs, voterLog) omitted
module raft {

  // ===========================================================================
  // Types
  // ===========================================================================

  type ServerId = str
  type Value = str

  type LogEntry = { term: int, value: Value }

  /// Flat message record (mirrors TLA+ style). Unused fields get defaults.
  type Message = {
    mtype: str,
    mterm: int,
    msource: ServerId,
    mdest: ServerId,
    // RequestVote
    mlastLogTerm: int,
    mlastLogIndex: int,
    // RequestVoteResponse
    mvoteGranted: bool,
    // AppendEntries
    mprevLogIndex: int,
    mprevLogTerm: int,
    mentries: List[LogEntry],
    mcommitIndex: int,
    // AppendEntriesResponse
    msuccess: bool,
    mmatchIndex: int,
  }

  // ===========================================================================
  // Constants
  // ===========================================================================

  pure val Server: Set[ServerId] = Set("s1", "s2", "s3")
  pure val Values: Set[Value] = Set("v1", "v2")

  pure val FOLLOWER = "Follower"
  pure val CANDIDATE = "Candidate"
  pure val LEADER = "Leader"
  pure val NIL = "Nil"

  pure val M_REQ_VOTE = "RequestVoteRequest"
  pure val M_REQ_VOTE_RESP = "RequestVoteResponse"
  pure val M_APP_ENT = "AppendEntriesRequest"
  pure val M_APP_ENT_RESP = "AppendEntriesResponse"

  pure val emptyMsg: Message = {
    mtype: "", mterm: 0, msource: NIL, mdest: NIL,
    mvoteGranted: false, mlastLogTerm: 0, mlastLogIndex: 0,
    mprevLogIndex: 0, mprevLogTerm: 0, mentries: [],
    mcommitIndex: 0, msuccess: false, mmatchIndex: 0,
  }

  // ===========================================================================
  // Helpers
  // ===========================================================================

  pure def min(a: int, b: int): int = if (a < b) a else b
  pure def max(a: int, b: int): int = if (a > b) a else b

  pure def isQuorum(s: Set[ServerId]): bool =
    s.size() * 2 > Server.size()

  /// Term of last log entry (1-based protocol), or 0 if empty.
  pure def lastTerm(xlog: List[LogEntry]): int =
    if (xlog.length() == 0) 0
    else xlog.nth(xlog.length() - 1).term

  pure def maxOfSet(s: Set[int]): int =
    s.fold(0, (acc, x) => if (x > acc) x else acc)

  // ===========================================================================
  // State Variables
  // ===========================================================================

  var messages: Set[Message]

  // Per-server state
  var currentTerm: ServerId -> int
  var state: ServerId -> str
  var votedFor: ServerId -> str

  var log: ServerId -> List[LogEntry]
  var commitIndex: ServerId -> int

  // Candidate state
  var votesResponded: ServerId -> Set[ServerId]
  var votesGranted: ServerId -> Set[ServerId]

  // Leader state
  var nextIndex: ServerId -> (ServerId -> int)
  var matchIndex: ServerId -> (ServerId -> int)

  // ===========================================================================
  // Unchanged helpers
  // ===========================================================================

  action unchanged_serverVars = all {
    currentTerm' = currentTerm,
    state' = state,
    votedFor' = votedFor,
  }

  action unchanged_candidateVars = all {
    votesResponded' = votesResponded,
    votesGranted' = votesGranted,
  }

  action unchanged_leaderVars = all {
    nextIndex' = nextIndex,
    matchIndex' = matchIndex,
  }

  action unchanged_logVars = all {
    log' = log,
    commitIndex' = commitIndex,
  }

  // ===========================================================================
  // Message helpers
  // ===========================================================================

  action send(m: Message): bool = all {
    messages' = messages.union(Set(m)),
  }

  action discard(m: Message): bool = all {
    messages' = messages.exclude(Set(m)),
  }

  action reply(response: Message, request: Message): bool = all {
    messages' = messages.exclude(Set(request)).union(Set(response)),
  }

  // ===========================================================================
  // Init
  // ===========================================================================

  action init = all {
    messages' = Set(),
    currentTerm' = Server.mapBy(_ => 1),
    state' = Server.mapBy(_ => FOLLOWER),
    votedFor' = Server.mapBy(_ => NIL),
    log' = Server.mapBy(_ => []),
    commitIndex' = Server.mapBy(_ => 0),
    votesResponded' = Server.mapBy(_ => Set()),
    votesGranted' = Server.mapBy(_ => Set()),
    nextIndex' = Server.mapBy(_ => Server.mapBy(_ => 1)),
    matchIndex' = Server.mapBy(_ => Server.mapBy(_ => 0)),
  }

  // ===========================================================================
  // State Transitions
  // ===========================================================================

  /// Server i restarts. Keeps currentTerm, votedFor, log.
  action restart(i: ServerId): bool = all {
    state' = state.set(i, FOLLOWER),
    votesResponded' = votesResponded.set(i, Set()),
    votesGranted' = votesGranted.set(i, Set()),
    nextIndex' = nextIndex.set(i, Server.mapBy(_ => 1)),
    matchIndex' = matchIndex.set(i, Server.mapBy(_ => 0)),
    commitIndex' = commitIndex.set(i, 0),
    messages' = messages,
    currentTerm' = currentTerm,
    votedFor' = votedFor,
    log' = log,
  }

  /// Server i times out and starts a new election.
  action timeout(i: ServerId): bool = all {
    state.get(i) == FOLLOWER or state.get(i) == CANDIDATE,
    state' = state.set(i, CANDIDATE),
    currentTerm' = currentTerm.setBy(i, t => t + 1),
    votedFor' = votedFor.set(i, NIL),
    votesResponded' = votesResponded.set(i, Set()),
    votesGranted' = votesGranted.set(i, Set()),
    messages' = messages,
    unchanged_leaderVars,
    unchanged_logVars,
  }

  /// Candidate i sends j a RequestVote request.
  action requestVote(i: ServerId, j: ServerId): bool = all {
    state.get(i) == CANDIDATE,
    not(j.in(votesResponded.get(i))),
    send({ ...emptyMsg,
      mtype: M_REQ_VOTE,
      mterm: currentTerm.get(i),
      mlastLogTerm: lastTerm(log.get(i)),
      mlastLogIndex: log.get(i).length(),
      msource: i,
      mdest: j,
    }),
    unchanged_serverVars,
    unchanged_candidateVars,
    unchanged_leaderVars,
    unchanged_logVars,
  }

  /// Leader i sends j an AppendEntries request (up to 1 entry).
  action appendEntries(i: ServerId, j: ServerId): bool = {
    val prevLogIndex = nextIndex.get(i).get(j) - 1
    val prevLogTerm =
      if (prevLogIndex > 0) log.get(i).nth(prevLogIndex - 1).term
      else 0
    val lastEntry = min(log.get(i).length(), nextIndex.get(i).get(j))
    val entries =
      if (nextIndex.get(i).get(j) > lastEntry) []
      else log.get(i).slice(nextIndex.get(i).get(j) - 1, lastEntry)
    all {
      i != j,
      state.get(i) == LEADER,
      send({ ...emptyMsg,
        mtype: M_APP_ENT,
        mterm: currentTerm.get(i),
        mprevLogIndex: prevLogIndex,
        mprevLogTerm: prevLogTerm,
        mentries: entries,
        mcommitIndex: min(commitIndex.get(i), lastEntry),
        msource: i,
        mdest: j,
      }),
      unchanged_serverVars,
      unchanged_candidateVars,
      unchanged_leaderVars,
      unchanged_logVars,
    }
  }

  /// Candidate i transitions to leader.
  action becomeLeader(i: ServerId): bool = all {
    state.get(i) == CANDIDATE,
    isQuorum(votesGranted.get(i)),
    state' = state.set(i, LEADER),
    nextIndex' = nextIndex.set(i, Server.mapBy(_ => log.get(i).length() + 1)),
    matchIndex' = matchIndex.set(i, Server.mapBy(_ => 0)),
    currentTerm' = currentTerm,
    votedFor' = votedFor,
    messages' = messages,
    unchanged_candidateVars,
    unchanged_logVars,
  }

  /// Leader i receives a client request to add v to the log.
  action clientRequest(i: ServerId, v: Value): bool = all {
    state.get(i) == LEADER,
    log' = log.setBy(i, l => l.append({ term: currentTerm.get(i), value: v })),
    messages' = messages,
    unchanged_serverVars,
    unchanged_candidateVars,
    unchanged_leaderVars,
    commitIndex' = commitIndex,
  }

  /// Leader i advances its commitIndex.
  action advanceCommitIndex(i: ServerId): bool = {
    val agreeIndexes = 1.to(log.get(i).length()).filter(index => {
      val agree = Set(i).union(Server.filter(k => matchIndex.get(i).get(k) >= index))
      isQuorum(agree)
    })
    val newCommitIndex =
      if (agreeIndexes.size() > 0 and
          log.get(i).nth(maxOfSet(agreeIndexes) - 1).term == currentTerm.get(i))
        maxOfSet(agreeIndexes)
      else
        commitIndex.get(i)
    all {
      state.get(i) == LEADER,
      commitIndex' = commitIndex.set(i, newCommitIndex),
      messages' = messages,
      unchanged_serverVars,
      unchanged_candidateVars,
      unchanged_leaderVars,
      log' = log,
    }
  }

  // ===========================================================================
  // Message Handlers
  // ===========================================================================

  /// Handle RequestVote request. i = recipient, j = sender.
  action handleRequestVoteRequest(i: ServerId, j: ServerId, m: Message): bool = {
    val logOk =
      if (m.mlastLogTerm > lastTerm(log.get(i))) true
      else if (m.mlastLogTerm == lastTerm(log.get(i))) m.mlastLogIndex >= log.get(i).length()
      else false
    val grant = m.mterm == currentTerm.get(i) and logOk and
      (votedFor.get(i) == NIL or votedFor.get(i) == j)
    all {
      m.mterm <= currentTerm.get(i),
      if (grant) votedFor' = votedFor.set(i, j)
      else       votedFor' = votedFor,
      reply(
        { ...emptyMsg,
          mtype: M_REQ_VOTE_RESP,
          mterm: currentTerm.get(i),
          mvoteGranted: grant,
          msource: i,
          mdest: j,
        },
        m
      ),
      state' = state,
      currentTerm' = currentTerm,
      unchanged_candidateVars,
      unchanged_leaderVars,
      unchanged_logVars,
    }
  }

  /// Handle RequestVote response. i = recipient, j = sender.
  action handleRequestVoteResponse(i: ServerId, j: ServerId, m: Message): bool = all {
    m.mterm == currentTerm.get(i),
    votesResponded' = votesResponded.setBy(i, s => s.union(Set(j))),
    if (m.mvoteGranted)
      votesGranted' = votesGranted.setBy(i, s => s.union(Set(j)))
    else
      votesGranted' = votesGranted,
    discard(m),
    unchanged_serverVars,
    unchanged_leaderVars,
    unchanged_logVars,
  }

  // --- AppendEntries sub-actions ---

  /// Reject: stale term or log mismatch.
  action rejectAppendEntries(i: ServerId, j: ServerId, m: Message): bool = {
    val logOk =
      if (m.mprevLogIndex == 0) true
      else if (m.mprevLogIndex > log.get(i).length()) false
      else m.mprevLogTerm == log.get(i).nth(m.mprevLogIndex - 1).term
    all {
      m.mterm < currentTerm.get(i) or
        (m.mterm == currentTerm.get(i) and state.get(i) == FOLLOWER and not(logOk)),
      reply(
        { ...emptyMsg,
          mtype: M_APP_ENT_RESP,
          mterm: currentTerm.get(i),
          msuccess: false,
          mmatchIndex: 0,
          msource: i,
          mdest: j,
        },
        m
      ),
      unchanged_serverVars,
      unchanged_logVars,
    }
  }

  /// Candidate steps down to follower on AppendEntries from current-term leader.
  action stepDownToFollower(i: ServerId, m: Message): bool = all {
    m.mterm == currentTerm.get(i),
    state.get(i) == CANDIDATE,
    state' = state.set(i, FOLLOWER),
    currentTerm' = currentTerm,
    votedFor' = votedFor,
    unchanged_logVars,
    messages' = messages,
  }

  /// Accept: entry already present or entries empty — reply success.
  action acceptAlreadyDone(i: ServerId, j: ServerId, m: Message): bool = {
    val index = m.mprevLogIndex + 1
    all {
      if (m.mentries.length() == 0) true
      else (log.get(i).length() >= index and
            log.get(i).nth(index - 1).term == m.mentries.nth(0).term),
      commitIndex' = commitIndex.set(i, m.mcommitIndex),
      reply(
        { ...emptyMsg,
          mtype: M_APP_ENT_RESP,
          mterm: currentTerm.get(i),
          msuccess: true,
          mmatchIndex: m.mprevLogIndex + m.mentries.length(),
          msource: i,
          mdest: j,
        },
        m
      ),
      unchanged_serverVars,
      log' = log,
    }
  }

  /// Accept: conflict — truncate log (remove last entry at conflict point).
  action acceptConflict(i: ServerId, m: Message): bool = {
    val index = m.mprevLogIndex + 1
    all {
      m.mentries.length() > 0,
      log.get(i).length() >= index,
      log.get(i).nth(index - 1).term != m.mentries.nth(0).term,
      log' = log.set(i, log.get(i).slice(0, log.get(i).length() - 1)),
      unchanged_serverVars,
      commitIndex' = commitIndex,
      messages' = messages,
    }
  }

  /// Accept: no conflict — append entry.
  action acceptAppend(i: ServerId, m: Message): bool = all {
    m.mentries.length() > 0,
    log.get(i).length() == m.mprevLogIndex,
    log' = log.setBy(i, l => l.append(m.mentries.nth(0))),
    unchanged_serverVars,
    commitIndex' = commitIndex,
    messages' = messages,
  }

  /// Handle AppendEntries request. i = recipient, j = sender.
  action handleAppendEntriesRequest(i: ServerId, j: ServerId, m: Message): bool = {
    val logOk =
      if (m.mprevLogIndex == 0) true
      else if (m.mprevLogIndex > log.get(i).length()) false
      else m.mprevLogTerm == log.get(i).nth(m.mprevLogIndex - 1).term
    all {
      m.mterm <= currentTerm.get(i),
      any {
        rejectAppendEntries(i, j, m),
        stepDownToFollower(i, m),
        all {
          m.mterm == currentTerm.get(i),
          state.get(i) == FOLLOWER,
          logOk,
          any {
            acceptAlreadyDone(i, j, m),
            acceptConflict(i, m),
            acceptAppend(i, m),
          },
        },
      },
      unchanged_candidateVars,
      unchanged_leaderVars,
    }
  }

  /// Handle AppendEntries response. i = recipient, j = sender.
  action handleAppendEntriesResponse(i: ServerId, j: ServerId, m: Message): bool = all {
    m.mterm == currentTerm.get(i),
    if (m.msuccess) all {
      nextIndex' = nextIndex.set(i, nextIndex.get(i).set(j, m.mmatchIndex + 1)),
      matchIndex' = matchIndex.set(i, matchIndex.get(i).set(j, m.mmatchIndex)),
    } else all {
      nextIndex' = nextIndex.set(i,
        nextIndex.get(i).set(j, max(nextIndex.get(i).get(j) - 1, 1))),
      matchIndex' = matchIndex,
    },
    discard(m),
    unchanged_serverVars,
    unchanged_candidateVars,
    unchanged_logVars,
  }

  /// Any RPC with a newer term causes recipient to step down.
  action updateTerm(i: ServerId, j: ServerId, m: Message): bool = all {
    m.mterm > currentTerm.get(i),
    currentTerm' = currentTerm.set(i, m.mterm),
    state' = state.set(i, FOLLOWER),
    votedFor' = votedFor.set(i, NIL),
    messages' = messages, // message stays for further processing
    unchanged_candidateVars,
    unchanged_leaderVars,
    unchanged_logVars,
  }

  /// Drop responses with stale terms.
  action dropStaleResponse(i: ServerId, j: ServerId, m: Message): bool = all {
    m.mterm < currentTerm.get(i),
    discard(m),
    unchanged_serverVars,
    unchanged_candidateVars,
    unchanged_leaderVars,
    unchanged_logVars,
  }

  /// Receive and dispatch a message.
  action receive(m: Message): bool = {
    val i = m.mdest
    val j = m.msource
    any {
      updateTerm(i, j, m),
      all { m.mtype == M_REQ_VOTE, handleRequestVoteRequest(i, j, m) },
      all { m.mtype == M_REQ_VOTE_RESP,
            any { dropStaleResponse(i, j, m), handleRequestVoteResponse(i, j, m) } },
      all { m.mtype == M_APP_ENT, handleAppendEntriesRequest(i, j, m) },
      all { m.mtype == M_APP_ENT_RESP,
            any { dropStaleResponse(i, j, m), handleAppendEntriesResponse(i, j, m) } },
    }
  }

  // ===========================================================================
  // Network
  // ===========================================================================

  /// Network drops a message.
  action dropMessage(m: Message): bool = all {
    discard(m),
    unchanged_serverVars,
    unchanged_candidateVars,
    unchanged_leaderVars,
    unchanged_logVars,
  }

  // ===========================================================================
  // Specification
  // ===========================================================================

  action step = any {
    nondet i = Server.oneOf()
    restart(i),

    nondet i = Server.oneOf()
    timeout(i),

    nondet i = Server.oneOf()
    nondet j = Server.oneOf()
    requestVote(i, j),

    nondet i = Server.oneOf()
    becomeLeader(i),

    nondet i = Server.oneOf()
    nondet v = Values.oneOf()
    clientRequest(i, v),

    nondet i = Server.oneOf()
    advanceCommitIndex(i),

    nondet i = Server.oneOf()
    nondet j = Server.oneOf()
    appendEntries(i, j),

    nondet m = messages.oneOf()
    receive(m),

    nondet m = messages.oneOf()
    dropMessage(m),
  }

  // ===========================================================================
  // Invariants
  // ===========================================================================

  /// Election safety: at most one leader per term.
  val electionSafety = Server.forall(i => Server.forall(j =>
    (state.get(i) == LEADER and state.get(j) == LEADER and
     currentTerm.get(i) == currentTerm.get(j)) implies i == j
  ))

  /// Log matching: if two logs have an entry at the same index with the same
  /// term, then the logs are identical through that index.
  val logMatching = Server.forall(i => Server.forall(j =>
    0.to(min(log.get(i).length(), log.get(j).length()) - 1).forall(k =>
      log.get(i).nth(k).term == log.get(j).nth(k).term implies
        0.to(k).forall(l => log.get(i).nth(l) == log.get(j).nth(l))
    )
  ))
}
