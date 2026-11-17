@IsTest
private class CaseReferenceResolverTest {
  @IsTest
  static void normalizesCommonWaysOfWritingACaseNumber() {
    Assert.areEqual('00001029', CaseReferenceResolver.normalize('1029'));
    Assert.areEqual('00001029', CaseReferenceResolver.normalize(' #1029 '));
    Assert.areEqual('00001029', CaseReferenceResolver.normalize('00001029'));
    Assert.isNull(CaseReferenceResolver.normalize(''));
    Assert.areEqual('abc', CaseReferenceResolver.normalize('abc'));
  }

  @IsTest
  static void resolvesByIdAndNumberAndIgnoresGarbage() {
    Case c = new Case(Subject = 'x');
    insert c;
    c = [SELECT Id, CaseNumber FROM Case WHERE Id = :c.Id];
    String fakeAccountId = '001000000000000AAA';

    Map<String, Case> found = CaseReferenceResolver.resolve(
      new List<String>{ c.Id, c.CaseNumber, 'not-a-case', fakeAccountId, null }
    );

    Assert.areEqual(c.Id, found.get(c.Id).Id);
    Assert.areEqual(c.Id, found.get(c.CaseNumber).Id);
    Assert.isFalse(found.containsKey('not-a-case'));
    Assert.isFalse(found.containsKey(fakeAccountId));
  }
}
