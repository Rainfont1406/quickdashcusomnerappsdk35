// Event-type constants for the customer behavior collection system.
// Collection-only: nothing in this system reads these back to personalize
// or recommend anything - see behavior_tracker.dart's header comment.

// Restaurant behavior
const String kEvtRestaurantOpened = 'restaurant_opened';
const String kEvtRestaurantFavorited = 'restaurant_favorited';
const String kEvtRestaurantUnfavorited = 'restaurant_unfavorited';
const String kEvtRestaurantRated = 'restaurant_rated'; // rating + review submitted together
const String kEvtRestaurantSelectedFromSearch = 'restaurant_selected_from_search';
const String kEvtRestaurantSelectedFromCuisineSearch = 'restaurant_selected_from_cuisine_search';
const String kEvtRestaurantInterest = 'restaurant_interest'; // dwell-threshold signal

// Product behavior
const String kEvtProductViewed = 'product_viewed';
const String kEvtProductInterest = 'product_interest'; // dwell-threshold signal
const String kEvtProductAddedToCart = 'product_added_to_cart';
const String kEvtProductRemovedFromCart = 'product_removed_from_cart';
const String kEvtProductQuantityChanged = 'product_quantity_changed';
const String kEvtProductOrdered = 'product_ordered';
// Combo Purchase Learning (2026-07-19, revised 2026-07-24) - fired
// ADDITIONALLY to kEvtProductOrdered (never instead of) whenever the
// ordered line item is a combo product, carrying price/comboProductIds/
// comboCategoryIds. Feeds comboOrderCount/comboPriceTotal/
// comboChildCountTotal/comboChildProductCounts (already read live by
// RecommendationEngine.comboEligibilityScore) and, additively,
// categoryInteractionCounts via comboCategoryIds - see
// behavior_tracker.dart's _computeSummaryUpdates for exactly how.
// comboProductIds is presence-only (deduped, no per-child quantity ever
// captured) and always weighted by comboQty (combo orders), never by a
// child's own serving-quantity within the combo - see that case's own
// comment for why that distinction matters here.
const String kEvtComboOrdered = 'combo_ordered';

// Search behavior
const String kEvtSearchPerformed = 'search_performed';

// Purchase behavior (2026-07-22: renamed from kEvtOrderPlaced/'order_placed'
// - fired by PurchaseCompletionListener once an order reaches
// ORDER_STATUS_COMPLETED, never at checkout/placement time anymore. A
// placed order is a purchase ATTEMPT, not a successful purchase - payment
// can still fail to settle, the vendor can reject it, etc. See
// PurchaseCompletionListener's own doc comment.)
const String kEvtOrderCompleted = 'order_completed';

// Offer behavior
const String kEvtOfferViewed = 'offer_viewed';
const String kEvtOfferClicked = 'offer_clicked';
// No kEvtOfferRedeemed - redemption is derived from order_completed's
// couponCode/couponId fields, not a separate event (see behavior_tracker.dart).

// Story behavior
const String kEvtStoryViewed = 'story_viewed';
const String kEvtStoryCompleted = 'story_completed';
const String kEvtStorySkipped = 'story_skipped';
const String kEvtStoryReplayed = 'story_replayed';

// Navigation behavior (high-level only)
const String kEvtNavOrderModeSwitched = 'nav_order_mode_switched';

// ── Phase 2 (2026-07-24): Restaurant Engagement / Search Conversion /
// Banner Analytics - COLLECTION ONLY, same posture as every event above.
// None of these are read by _computeSummaryUpdates (behavior_summary, the
// doc RecommendationEngine actually consumes) - they flow into their own
// sibling collections (restaurantEngagement, bannerAnalytics, per-user
// bannerClicks) so this phase cannot alter any existing recommendation
// input even by accident. See behavior_tracker.dart's flush() for where
// they land.

// Fired once per restaurant-menu visit, at screen dispose, carrying the
// ALREADY-COMPUTED session totals (duration, product views, categories
// browsed, cart adds) - the screen-local counters are the single source of
// truth, this event is just how they reach Firestore. Doubles as the
// Search Conversion record when entrySource is Search/Cuisine (see
// BehaviorTracker.startRestaurantSession) - deliberately ONE doc per visit
// rather than a second parallel "search conversion" collection with the
// same fields.
const String kEvtRestaurantSessionEnded = 'restaurant_session_ended';

// Fired once per order PLACEMENT (checkout success), distinct from
// kEvtOrderCompleted (which fires later, post-fulfillment, and DOES feed
// behavior_summary/preference learning via PurchaseCompletionListener).
// This one exists purely to mark restaurantEngagement.orderPlaced /
// bannerAnalytics.ordersGenerated - an order can be placed and then
// cancelled/fail, which is exactly why this is kept separate from the
// completion signal rather than reusing or renaming it.
const String kEvtOrderPlacedForEngagement = 'order_placed_for_engagement';

// Banner behavior (Home top/middle banner carousels).
const String kEvtBannerImpression = 'banner_impression';
const String kEvtBannerClicked = 'banner_clicked';

// "Interest duration" config - a single bounded Timer per screen visit
// (started in initState, cancelled in dispose if left early), never a
// continuous/repeating timer. See behavior_tracker.dart.
const int kDwellThresholdSeconds = 9;

// Retention split (2026-09-20) - the 3->12mo extension below was measured
// live to cost every user's fetch ~4x the bytes, but only ~5 of the ~19
// behavior_summary fields (searchDayHits, topSearchKeywords, the 4
// searchConfidence* maps) are ever read by anything that needs 12 months
// of history (BehaviorSummarySnapshot.crossSessionSearchInterestFor and
// friends). Every other field - productViewCounts, categoryInteractionCounts,
// avgOrderValue, combo/veg counters, etc. - only ever feeds RecommendationEngine's
// CURRENT-preference scoring, which has no stated need to look back a full
// year. Splitting into two sibling subcollections (behavior_summary, the
// original shape minus the 5 search fields, kept at the original 3-month
// retention; behavior_summary_search, ONLY those 5 fields, kept at 12
// months) preserves both consumers' existing behavior while cutting the
// typical fetch's payload roughly 60-65% (measured across real production
// accounts, see 2026-09-20 session notes) - see BehaviorTracker._flush's
// split write and FirebaseHelper._loadBehaviorSummary's split read.
//
// Known, accepted migration gap: any search data written into the OLD,
// unsplit behavior_summary shape before this shipped is NOT retroactively
// copied into behavior_summary_search - it simply stops being read once
// this ships. Confirmed acceptable at ship time: no production account had
// more than 3 months of history yet (Cross-Session Search Interest's own
// 12-month benefit had never actually been reachable by anyone), so there
// was no real search history for any user to lose.
const int kBehaviorSummaryCoreRetentionMonths = 3;

// How many trailing months of behavior_summary_search docs are retained
// (originally applied to the single behavior_summary collection, extended
// 3 -> 12 months 2026-07-18 for Cross-Session Search Interest / long-term
// preference signals - see RECOMMENDATION_SYSTEM_ARCHITECTURE.html Section
// 19; narrowed to just the search-specific fields 2026-09-20, see
// kBehaviorSummaryCoreRetentionMonths above for why). Shared between
// behavior_tracker.dart's pruning logic and FirebaseHelper.dart's fetch
// window - MUST stay in sync between the two, which is exactly why this
// lives in one place instead of two magic numbers.
const int kBehaviorSummaryRetentionMonths = 12;
