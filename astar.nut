/* Generic A* that can be run in small steps.
 * The callbacks get a context object (the job) as their first argument:
 *   nb(ctx, key, kind) -> array of [key, cost, kind]
 *   goal(ctx, key, kind) -> bool
 *   h(ctx, key)        -> estimated remaining cost
 * kind says how a node was reached: 0 = step, 1 = bridge, 2 = tunnel. */
class AStar {
  open = null;
  g = null;
  came = null;
  kind = null;
  closed = null;
  ctx = null;
  nb = null;
  goal = null;
  h = null;
  limit = 0;
  examined = 0;
  found = -1;
  h0 = -1;       // estimate at the start
  best_h = -1;   // closest the search got to the goal

  /* How close the search got to the goal, 0..100. */
  function Closeness() {
    if (this.h0 <= 0 || this.best_h < 0) return 0;
    return 100 - this.best_h * 100 / this.h0;
  }

  constructor(ctx, starts, nb, goal, h, limit) {
    this.open = GSPriorityQueue();
    this.g = {};
    this.came = {};
    this.kind = {};
    this.closed = {};
    this.ctx = ctx;
    this.nb = nb;
    this.goal = goal;
    this.h = h;
    this.limit = limit;
    foreach (k in starts) {
      this.g.rawset(k, 0);
      this.came.rawset(k, -1);
      this.kind.rawset(k, 0);
      this.open.Insert(k, h(ctx, k));
    }
  }

  /* Returns 0 = still running, 1 = found, -1 = no route. */
  function Step(n) {
    for (local i = 0; i < n; i++) {
      // a button was pressed: return so the main loop can handle it
      if (i > 0 && i % 50 == 0 && GSEventController.IsEventWaiting()) return 0;
      if (this.open.IsEmpty()) return -1;
      local cur = this.open.Pop();
      if (this.closed.rawin(cur)) continue;
      this.closed.rawset(cur, true);
      if (this.goal(this.ctx, cur, this.kind.rawget(cur))) {
        this.found = cur;
        return 1;
      }
      if (++this.examined > this.limit) return -1;
      local hc = this.h(this.ctx, cur);
      if (this.h0 < 0) this.h0 = hc;
      if (hc < this.best_h || this.best_h < 0) this.best_h = hc;
      local gc = this.g.rawget(cur);
      foreach (e in this.nb(this.ctx, cur, this.kind.rawget(cur))) {
        local k = e[0];
        if (this.closed.rawin(k)) continue;
        local ng = gc + e[1];
        if (!this.g.rawin(k) || ng < this.g.rawget(k)) {
          this.g.rawset(k, ng);
          this.came.rawset(k, cur);
          this.kind.rawset(k, e[2]);
          this.open.Insert(k, ng + this.h(this.ctx, k));
        }
      }
    }
    return 0;
  }

  /* Path as two arrays: tiles and how each tile was reached. */
  function Path() {
    local tiles = [], kinds = [];
    for (local k = this.found; k != -1; k = this.came.rawget(k)) {
      tiles.append(K_Tile(k));
      kinds.append(this.kind.rawget(k));
    }
    tiles.reverse();
    kinds.reverse();
    return { tiles = tiles, kinds = kinds };
  }
}
