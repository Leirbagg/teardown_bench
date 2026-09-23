class_name ProcedureCheck
extends RefCounted
## Vérifie qu'une procédure tirée d'un guide se joue telle quelle sur le graphe de l'appareil.
##
## C'est le lien entre les deux : le graphe dit ce qui est possible, la procédure dit ce que
## fait le réparateur. Si l'ordre du guide force une pièce ou bute sur une pièce cachée, ce
## n'est pas le guide qui a tort — c'est notre modélisation. Rejouer la séquence est donc la
## meilleure relecture automatique qu'on puisse avoir de nos données.

const Outcome = DisassemblyResult.Outcome


## Erreurs de la procédure, vide si elle se joue du premier coup.
static func errors_for(device: DeviceDefinition, procedure: DeviceDefinition.Procedure) -> Array[String]:
	var errors: Array[String] = []
	var where: String = "%s/%s" % [device.id, procedure.id]

	var target: ComponentDefinition = device.component_for_role(procedure.target_role)
	if target == null:
		errors.append("[unknown_ref] %s : aucun composant ne porte le rôle '%s'" % [where, procedure.target_role])
		return errors

	var seen: Dictionary[String, bool] = {}
	var state: DisassemblyState = DisassemblyState.new(device)
	for i: int in procedure.steps.size():
		var step: String = procedure.steps[i]
		if not device.has_component(step):
			errors.append("[unknown_ref] %s, étape %d : '%s' n'existe pas" % [where, i + 1, step])
			return errors
		if seen.has(step):
			errors.append("[bad_value] %s, étape %d : '%s' est retiré deux fois" % [where, i + 1, step])
			return errors
		seen[step] = true
		var result: DisassemblyResult = state.commit_remove(step)
		if result.outcome != Outcome.REMOVED:
			errors.append("[step_blocked] %s, étape %d : retirer '%s' donne %s, pas REMOVED%s" % [
				where, i + 1, step, Outcome.keys()[result.outcome],
				" (retenu par %s)" % ", ".join(result.blockers) if not result.blockers.is_empty() else ""])
			return errors

	# Le but de la procédure : pouvoir poser une pièce neuve à la fin.
	var replaced: DisassemblyResult = state.replace(target.id)
	if replaced.outcome != Outcome.REPLACED:
		errors.append("[target_unreachable] %s : la séquence ne permet pas de remplacer '%s' (%s)" % [
			where, target.id, Outcome.keys()[replaced.outcome]])
	if not state.broken_ids().is_empty():
		errors.append("[step_breaks] %s : la séquence casse %s" % [where, ", ".join(state.broken_ids())])
	return errors


## Erreurs de toutes les procédures d'un appareil.
static func errors_for_device(device: DeviceDefinition) -> Array[String]:
	var errors: Array[String] = []
	var ids: PackedStringArray = PackedStringArray()
	for procedure: DeviceDefinition.Procedure in device.procedures:
		if procedure.id in ids:
			errors.append("[duplicate_id] %s : procédure '%s' en double" % [device.id, procedure.id])
			continue
		ids.append(procedure.id)
		errors.append_array(errors_for(device, procedure))
	return errors
