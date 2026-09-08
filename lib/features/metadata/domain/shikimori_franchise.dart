class ShikimoriFranchiseLink {
  const ShikimoriFranchiseLink(
    this.sourceMalId,
    this.targetMalId,
    this.relation,
  );
  final int sourceMalId;
  final int targetMalId;
  final String relation;
}

class ShikimoriFranchiseMember {
  const ShikimoriFranchiseMember({
    required this.shikimoriId,
    required this.malId,
    this.name = '',
    this.russian = '',
    this.posterUrl = '',
    this.episodes,
    this.score = 0,
  });

  final int shikimoriId;
  final int malId;
  final String name;
  final String russian;
  final String posterUrl;
  final int? episodes;
  final double score;
}

class ShikimoriFranchise {
  const ShikimoriFranchise({
    this.malIds = const [],
    this.links = const [],
    this.members = const [],
    this.unmappedCount = 0,
  });
  final List<int> malIds;
  final List<ShikimoriFranchiseLink> links;
  final List<ShikimoriFranchiseMember> members;
  final int unmappedCount;
}
