/// Answering/hanging up is not a decision about whether an SOS is real.
bool needsOperatorSosAlert(Map<String, dynamic> row) {
  if (row['alert_in_range'] == false) return false;
  if (row['decision'] == 'discarded' || row['attention'] == 'resolved') {
    return false;
  }
  return row['decision'] == 'pending' || row['support_requested'] == true;
}
