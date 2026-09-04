import 'watch_order.dart';

/// Resolves only discovered franchise members. Relations never expand membership.
class WatchOrderResolver {
  const WatchOrderResolver();

  WatchOrder resolve(
    Iterable<WatchOrderMedia> media, {
    int missingEntries = 0,
  }) {
    final nodes = {
      for (final node in media)
        if (node.id > 0) node.id: node,
    };
    if (nodes.isEmpty) return WatchOrder(missingEntries: missingEntries);
    int byDate(int a, int b) {
      final date = nodes[a]!.startDate.compareTo(nodes[b]!.startDate);
      if (date != 0) return date;
      final format = _formatRank(
        nodes[a]!.format,
      ).compareTo(_formatRank(nodes[b]!.format));
      return format != 0 ? format : a.compareTo(b);
    }

    final ids = nodes.keys.toList()..sort(byDate);
    final strong = {for (final id in ids) id: <int>{}};
    final parents = <int, Map<int, int>>{};
    final summaries = <int>{};
    void attach(int parent, int child, int priority) {
      final candidates = parents.putIfAbsent(child, () => {});
      if (priority < (candidates[parent] ?? 99)) candidates[parent] = priority;
    }

    for (final node in nodes.values) {
      for (final relation in node.relations) {
        final target = relation.targetId;
        if (target == node.id || !nodes.containsKey(target)) continue;
        switch (relation.type) {
          case 'PREQUEL':
            strong[target]!.add(node.id);
          case 'SEQUEL':
            strong[node.id]!.add(target);
          case 'PARENT':
            attach(target, node.id, 0);
          case 'SIDE_STORY':
            attach(node.id, target, 1);
          case 'SUMMARY':
          case 'COMPILATION':
            summaries.add(target);
            attach(node.id, target, 2);
        }
      }
    }

    bool canBeMain(int id) =>
        nodes[id]!.format != 'MUSIC' && !summaries.contains(id);
    final main = ids
        .where(
          (id) =>
              canBeMain(id) &&
              !parents.containsKey(id) &&
              const {'TV', 'TV_SHORT', 'ONA'}.contains(nodes[id]!.format),
        )
        .toSet();
    final neighbours = {for (final id in ids) id: <int>{}};
    for (final source in ids) {
      for (final target in strong[source]!) {
        neighbours[source]!.add(target);
        neighbours[target]!.add(source);
      }
    }
    // Movie/OVA-only franchises also have main stories. Side branches cannot
    // seed the mainline, but a direct strong connection can promote a movie/OVA.
    if (main.isEmpty) {
      main.addAll(
        ids.where(
          (id) =>
              canBeMain(id) &&
              !parents.containsKey(id) &&
              (nodes[id]!.format == 'MOVIE' || neighbours[id]!.isNotEmpty),
        ),
      );
    }
    final queue = main.toList();
    for (var i = 0; i < queue.length; i++) {
      for (final neighbour in neighbours[queue[i]]!) {
        if (canBeMain(neighbour) && main.add(neighbour)) queue.add(neighbour);
      }
    }

    // Condense contradictory strong relations conceptually: replace only edges
    // inside each SCC by a stable date-ordered chain. All cross-SCC constraints
    // survive, including incoming edges to any member of a cycle.
    final components = _components(ids, strong);
    final dag = {
      for (final id in ids) id: <int>{...strong[id]!},
    };
    var hasCycles = false;
    for (final component in components) {
      if (component.length < 2) continue;
      hasCycles = true;
      component.sort(byDate);
      final members = component.toSet();
      final incoming = <int>{};
      final outgoing = <int>{};
      for (final source in ids) {
        if (members.contains(source)) {
          outgoing.addAll(dag[source]!.where((id) => !members.contains(id)));
          dag[source]!.clear();
        } else if (dag[source]!.any(members.contains)) {
          incoming.add(source);
          dag[source]!.removeAll(members);
        }
      }
      for (final source in incoming) {
        dag[source]!.add(component.first);
      }
      dag[component.last]!.addAll(outgoing);
      for (var i = 1; i < component.length; i++) {
        dag[component[i - 1]]!.add(component[i]);
      }
    }

    final base = _topological(ids, dag, byDate);
    final mainOrder = base.where(main.contains).toList();
    final anchors = <int, int>{};
    final directParents = <int, int>{};

    // Follow parent chains (e.g. a special of an OVA), with loop protection.
    int? anchor(int id, Set<int> visiting) {
      if (main.contains(id)) return id;
      if (!visiting.add(id)) return null;
      final candidates = (parents[id]?.keys.toList() ?? <int>[])
        ..sort((a, b) {
          final rank = parents[id]![a]!.compareTo(parents[id]![b]!);
          if (rank != 0) return rank;
          final date = nodes[id]!.startDate;
          final aBefore = nodes[a]!.startDate.compareTo(date) <= 0;
          final bBefore = nodes[b]!.startDate.compareTo(date) <= 0;
          if (aBefore != bBefore) return aBefore ? -1 : 1;
          return aBefore ? byDate(b, a) : byDate(a, b);
        });
      for (final parent in candidates) {
        if (_reachable(id, parent, dag)) continue;
        // Share the visited set across branches: a dense malformed parent graph
        // must not enumerate exponentially many paths to the same nodes.
        final root = anchor(parent, visiting);
        if (root != null) {
          directParents[id] = parent;
          return root;
        }
      }
      return null;
    }

    for (final id in ids.where((id) => !main.contains(id))) {
      final root = anchor(id, {});
      if (root != null) anchors[id] = root;
    }
    // Adjacency is a soft preference. Add parent precedence only when it is
    // compatible with all strong constraints and already accepted attachments.
    for (final id in ids) {
      final parent = directParents[id];
      if (parent != null && !_reachable(id, parent, dag)) {
        dag[parent]!.add(id);
      } else {
        directParents.remove(id);
        anchors.remove(id);
      }
    }

    final buckets = <int, List<int>>{};
    for (final id in ids.where((id) => !main.contains(id))) {
      var slot = anchors[id] == null ? -1 : mainOrder.indexOf(anchors[id]!);
      if (anchors[id] == null) {
        // Insert after the closest preceding release, even when strong edges
        // made the mainline itself non-chronological.
        int? closest;
        for (final mainId in mainOrder) {
          if (nodes[mainId]!.startDate.year != null &&
              nodes[mainId]!.startDate.compareTo(nodes[id]!.startDate) <= 0 &&
              (closest == null || byDate(closest, mainId) < 0)) {
            closest = mainId;
          }
        }
        if (nodes[id]!.startDate.year == null) {
          slot = mainOrder.length - 1;
        } else if (closest != null) {
          slot = mainOrder.indexOf(closest);
        }
      }
      buckets.putIfAbsent(slot, () => []).add(id);
    }
    final preferred = <int>[...?buckets[-1]];
    for (var i = 0; i < mainOrder.length; i++) {
      preferred.add(mainOrder[i]);
      preferred.addAll(buckets[i] ?? []);
    }
    final rank = {for (var i = 0; i < preferred.length; i++) preferred[i]: i};
    final ordered = _topological(
      ids,
      dag,
      (a, b) => rank[a]!.compareTo(rank[b]!),
    );
    return WatchOrder(
      entries: [
        for (final id in ordered)
          WatchOrderEntry(
            media: nodes[id]!,
            isMainline: main.contains(id),
            parentId: directParents[id],
          ),
      ],
      hasCycles: hasCycles,
      missingEntries: missingEntries,
    );
  }

  static int _formatRank(String format) => switch (format) {
    'TV' => 0,
    'TV_SHORT' => 1,
    'ONA' => 2,
    'MOVIE' => 3,
    'OVA' => 4,
    'SPECIAL' => 5,
    'MUSIC' => 6,
    _ => 7,
  };

  static bool _reachable(int from, int to, Map<int, Set<int>> graph) {
    final pending = <int>[from];
    final seen = <int>{};
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (id == to) return true;
      if (seen.add(id)) pending.addAll(graph[id]!);
    }
    return false;
  }

  static List<int> _topological(
    List<int> ids,
    Map<int, Set<int>> graph,
    Comparator<int> compare,
  ) {
    final degrees = {for (final id in ids) id: 0};
    for (final targets in graph.values) {
      for (final id in targets) {
        degrees[id] = degrees[id]! + 1;
      }
    }
    final ready = ids.where((id) => degrees[id] == 0).toList();
    final result = <int>[];
    while (ready.isNotEmpty) {
      ready.sort(compare);
      final id = ready.removeAt(0);
      result.add(id);
      for (final target in graph[id]!) {
        degrees[target] = degrees[target]! - 1;
        if (degrees[target] == 0) ready.add(target);
      }
    }
    return result;
  }

  static List<List<int>> _components(List<int> ids, Map<int, Set<int>> graph) {
    var index = 0;
    final indexes = <int, int>{};
    final low = <int, int>{};
    final stack = <int>[];
    final active = <int>{};
    final result = <List<int>>[];
    void visit(int id) {
      indexes[id] = low[id] = index++;
      stack.add(id);
      active.add(id);
      for (final target in graph[id]!) {
        if (!indexes.containsKey(target)) {
          visit(target);
          if (low[target]! < low[id]!) low[id] = low[target]!;
        } else if (active.contains(target) && indexes[target]! < low[id]!) {
          low[id] = indexes[target]!;
        }
      }
      if (low[id] != indexes[id]) return;
      final component = <int>[];
      int member;
      do {
        member = stack.removeLast();
        active.remove(member);
        component.add(member);
      } while (member != id);
      result.add(component);
    }

    for (final id in ids) {
      if (!indexes.containsKey(id)) visit(id);
    }
    return result;
  }
}
