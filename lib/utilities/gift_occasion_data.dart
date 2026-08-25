import 'package:flutter/material.dart';

class GiftOccasion {
  final String name;
  final IconData icon;

  /// Occasion-specific default wording, pre-filled into the message
  /// field the moment this occasion is picked (still fully editable).
  final String defaultMessage;
  const GiftOccasion({required this.name, required this.icon, required this.defaultMessage});
}

class GiftOccasionCategory {
  final String categoryName;
  final List<GiftOccasion> occasions;
  const GiftOccasionCategory({required this.categoryName, required this.occasions});
}

/// Gift occasions grouped the same way the reference design shows them:
/// All Gifts, Celebrations, Events, Holidays, Milestones, Everyday —
/// each a horizontally-scrolling row of icon tiles under its own
/// section header, covering occasions across the whole year. Every
/// occasion carries its own default message wording.
const List<GiftOccasionCategory> kGiftOccasionCategories = [
  GiftOccasionCategory(
    categoryName: 'All Gifts',
    occasions: [
      GiftOccasion(name: 'Generic', icon: Icons.card_giftcard_outlined, defaultMessage: 'A little something for you!'),
      GiftOccasion(name: 'Birthday', icon: Icons.cake_outlined, defaultMessage: 'Happy Birthday! 🎂'),
      GiftOccasion(name: 'Christmas', icon: Icons.park_outlined, defaultMessage: 'Merry Christmas! 🎄'),
      GiftOccasion(name: 'New Year', icon: Icons.auto_awesome_outlined, defaultMessage: 'Happy New Year! 🎉'),
      GiftOccasion(name: 'Wedding', icon: Icons.diamond_outlined, defaultMessage: 'Congratulations on your wedding! 💍'),
      GiftOccasion(name: 'Graduation', icon: Icons.school_outlined, defaultMessage: 'Congrats, graduate! 🎓'),
      GiftOccasion(name: 'Thank You', icon: Icons.thumb_up_outlined, defaultMessage: 'Thank you so much!'),
      GiftOccasion(name: "Valentine's Day", icon: Icons.favorite_outline_rounded, defaultMessage: 'Happy Valentine\'s Day ❤️'),
    ],
  ),
  GiftOccasionCategory(
    categoryName: 'Celebrations',
    occasions: [
      GiftOccasion(name: 'Black Friday', icon: Icons.shopping_bag_outlined, defaultMessage: 'Treat yourself this Black Friday!'),
      GiftOccasion(name: 'Christmas', icon: Icons.park_outlined, defaultMessage: 'Merry Christmas! 🎄'),
      GiftOccasion(name: 'Congratulations', icon: Icons.celebration_outlined, defaultMessage: 'Congratulations! 🎉'),
      GiftOccasion(name: 'New Year', icon: Icons.auto_awesome_outlined, defaultMessage: 'Happy New Year! 🎉'),
      GiftOccasion(name: "New Year's Eve", icon: Icons.nightlife_outlined, defaultMessage: 'Cheers to the new year!'),
      GiftOccasion(name: 'Retirement', icon: Icons.beach_access_outlined, defaultMessage: 'Happy retirement — enjoy every day!'),
      GiftOccasion(name: 'Promotion', icon: Icons.trending_up_rounded, defaultMessage: 'Congrats on the promotion!'),
      GiftOccasion(name: 'Housewarming', icon: Icons.house_outlined, defaultMessage: 'Congrats on the new place!'),
    ],
  ),
  GiftOccasionCategory(
    categoryName: 'Events',
    occasions: [
      GiftOccasion(name: 'Generic', icon: Icons.card_giftcard_outlined, defaultMessage: 'A little something for you!'),
      GiftOccasion(name: 'Graduation', icon: Icons.school_outlined, defaultMessage: 'Congrats, graduate! 🎓'),
      GiftOccasion(name: 'Hanukkah', icon: Icons.local_fire_department_outlined, defaultMessage: 'Happy Hanukkah!'),
      GiftOccasion(name: 'Baby Shower', icon: Icons.child_friendly_outlined, defaultMessage: 'So excited for you both!'),
      GiftOccasion(name: 'Gender Reveal', icon: Icons.wc_outlined, defaultMessage: 'Can\'t wait to meet the little one!'),
      GiftOccasion(name: 'Engagement', icon: Icons.favorite_border_rounded, defaultMessage: 'Congrats on your engagement! 💕'),
      GiftOccasion(name: 'Bridal Shower', icon: Icons.local_florist_outlined, defaultMessage: 'Wishing you all the best!'),
      GiftOccasion(name: 'Farewell', icon: Icons.flight_takeoff_outlined, defaultMessage: 'We\'ll miss you — good luck!'),
    ],
  ),
  GiftOccasionCategory(
    categoryName: 'Holidays',
    occasions: [
      GiftOccasion(name: 'Thank You', icon: Icons.thumb_up_outlined, defaultMessage: 'Thank you so much!'),
      GiftOccasion(name: "Valentine's Day", icon: Icons.favorite_outline_rounded, defaultMessage: 'Happy Valentine\'s Day ❤️'),
      GiftOccasion(name: 'Wedding', icon: Icons.diamond_outlined, defaultMessage: 'Congratulations on your wedding! 💍'),
      GiftOccasion(name: 'Anniversary', icon: Icons.local_bar_outlined, defaultMessage: 'Happy Anniversary!'),
      GiftOccasion(name: 'Birthday', icon: Icons.cake_outlined, defaultMessage: 'Happy Birthday! 🎂'),
      GiftOccasion(name: "Mother's Day", icon: Icons.emoji_nature_outlined, defaultMessage: 'Happy Mother\'s Day! 💐'),
      GiftOccasion(name: "Father's Day", icon: Icons.emoji_events_outlined, defaultMessage: 'Happy Father\'s Day!'),
      GiftOccasion(name: 'Easter', icon: Icons.egg_outlined, defaultMessage: 'Happy Easter!'),
      GiftOccasion(name: 'Eid', icon: Icons.mosque_outlined, defaultMessage: 'Eid Mubarak!'),
      GiftOccasion(name: 'Ramadan', icon: Icons.nights_stay_outlined, defaultMessage: 'Ramadan Kareem!'),
      GiftOccasion(name: "Independence Day", icon: Icons.flag_outlined, defaultMessage: 'Happy Independence Day!'),
      GiftOccasion(name: 'Halloween', icon: Icons.dark_mode_outlined, defaultMessage: 'Happy Halloween! 🎃'),
      GiftOccasion(name: 'Thanksgiving', icon: Icons.restaurant_outlined, defaultMessage: 'Happy Thanksgiving!'),
    ],
  ),
  GiftOccasionCategory(
    categoryName: 'Milestones',
    occasions: [
      GiftOccasion(name: 'New Job', icon: Icons.work_outline_rounded, defaultMessage: 'Congrats on the new job!'),
      GiftOccasion(name: 'New Home', icon: Icons.villa_outlined, defaultMessage: 'Congrats on the new home!'),
      GiftOccasion(name: 'New Baby', icon: Icons.child_care_outlined, defaultMessage: 'Congratulations on your new baby! 👶'),
      GiftOccasion(name: 'Get Well Soon', icon: Icons.healing_outlined, defaultMessage: 'Get well soon!'),
      GiftOccasion(name: 'Condolences', icon: Icons.local_florist_outlined, defaultMessage: 'Thinking of you.'),
      GiftOccasion(name: 'Good Luck', icon: Icons.emoji_objects_outlined, defaultMessage: 'Good luck — you\'ve got this!'),
    ],
  ),
  GiftOccasionCategory(
    categoryName: 'Everyday',
    occasions: [
      GiftOccasion(name: 'Just Because', icon: Icons.emoji_emotions_outlined, defaultMessage: 'Just because!'),
      GiftOccasion(name: 'Miss You', icon: Icons.favorite_outline_rounded, defaultMessage: 'Miss you!'),
      GiftOccasion(name: 'Support', icon: Icons.volunteer_activism_outlined, defaultMessage: 'Thinking of you — here for you.'),
      GiftOccasion(name: 'Appreciation', icon: Icons.star_border_rounded, defaultMessage: 'Just showing my appreciation!'),
      GiftOccasion(name: 'Exam Success', icon: Icons.fact_check_outlined, defaultMessage: 'Well done on your exams!'),
      GiftOccasion(name: 'Welcome Back', icon: Icons.waving_hand_outlined, defaultMessage: 'Welcome back!'),
    ],
  ),
];
