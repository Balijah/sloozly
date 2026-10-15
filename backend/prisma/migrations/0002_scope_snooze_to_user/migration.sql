DROP INDEX "penalties_occurrence_id_snooze_number_key";
CREATE UNIQUE INDEX "penalties_user_id_occurrence_id_snooze_number_key" ON "penalties"("user_id", "occurrence_id", "snooze_number");
