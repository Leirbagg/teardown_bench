class_name Workshop
extends RefCounted
## Progression de l'atelier : argent, réputation et niveau débloqué. Le joueur n'est jamais
## bloqué : l'argent ne descend pas sous zéro et il n'y a pas de dette (GDD, pilier 3).

signal money_changed(money: int)
signal reputation_changed(reputation: float)

const STARTING_MONEY: int = 120
## Moyenne des notes des dernières réparations.
const RATING_WINDOW: int = 10
## Réputation minimale pour débloquer le tier 2, puis le tier 3.
const TIER_THRESHOLDS: Array[float] = [3.5, 4.5]

var money: int = STARTING_MONEY
var day: int = 1

var _ratings: Array[int] = []
var _jobs_done: int = 0


static func from_dict(data: Dictionary) -> Workshop:
	var workshop: Workshop = Workshop.new()
	workshop.money = int(data.get("money", STARTING_MONEY))
	workshop.day = maxi(1, int(data.get("day", 1)))
	workshop._jobs_done = int(data.get("jobs_done", 0))
	for rating: Variant in data.get("ratings", []):
		workshop._ratings.append(int(rating))
	return workshop


func to_dict() -> Dictionary:
	return {"money": money, "day": day, "jobs_done": _jobs_done, "ratings": _ratings}


## Note moyenne sur les dernières réparations, 0 tant qu'aucune n'a compté.
func reputation() -> float:
	if _ratings.is_empty():
		return 0.0
	var total: int = 0
	for rating: int in _ratings:
		total += rating
	return float(total) / _ratings.size()


## Réparations terminées par le joueur, hors mode solution.
func jobs_done() -> int:
	return _jobs_done


## Tier de pannes et d'appareils accessible, à partir de 1.
func max_tier() -> int:
	var tier: int = 1
	for threshold: float in TIER_THRESHOLDS:
		if reputation() >= threshold:
			tier += 1
	return tier


## Encaisse une réparation terminée et enregistre sa note. Renvoie le gain net (0 si elle ne
## compte pas : non terminée ou assistée).
func record_job(report: RepairReport) -> int:
	if not report.completed or report.assisted:
		return 0
	_jobs_done += 1
	_ratings.append(report.stars)
	if _ratings.size() > RATING_WINDOW:
		_ratings = _ratings.slice(_ratings.size() - RATING_WINDOW)
	var net: int = report.earnings()
	money = maxi(money + net, 0)
	money_changed.emit(money)
	reputation_changed.emit(reputation())
	return net


func finish_day() -> void:
	day += 1
