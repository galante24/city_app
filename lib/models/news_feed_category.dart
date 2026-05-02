/// Вкладки городской ленты и значение `posts.category` в БД.
enum NewsCategory { smi, administration, discussion }

String categoryLabelRu(NewsCategory c) {
  return switch (c) {
    NewsCategory.smi => 'СМИ',
    NewsCategory.administration => 'Важные',
    NewsCategory.discussion => 'Обсуждение',
  };
}

String categoryToDb(NewsCategory c) {
  return switch (c) {
    NewsCategory.smi => 'smi',
    NewsCategory.administration => 'administration',
    NewsCategory.discussion => 'discussion',
  };
}

NewsCategory categoryFromDb(String? s) {
  switch (s) {
    case 'administration':
      return NewsCategory.administration;
    case 'discussion':
      return NewsCategory.discussion;
    case 'smi':
    default:
      return NewsCategory.smi;
  }
}
