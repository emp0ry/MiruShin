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

class ShikimoriFranchise {
  const ShikimoriFranchise({
    this.malIds = const [],
    this.links = const [],
    this.unmappedCount = 0,
  });
  final List<int> malIds;
  final List<ShikimoriFranchiseLink> links;
  final int unmappedCount;
}
