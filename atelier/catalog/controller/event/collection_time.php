<?php
namespace Opencart\Catalog\Controller\Extension\Atelier\Event;
class CollectionTime extends \Opencart\System\Engine\Controller {
	// Opening hours per weekday: 1 = Monday ... 7 = Sunday, null = closed
	private const HOURS = [
		1 => ['08:00', '20:00'],
		2 => ['08:00', '20:00'],
		3 => ['08:00', '20:00'],
		4 => ['08:00', '20:00'],
		5 => ['08:00', '20:00'],
		6 => ['09:00', '18:00'],
		7 => ['09:00', '18:00'],
	];
	private const MIN_LEAD = 60;   // a chosen time must be at least this many minutes ahead
	private const SLOT_STEP = 15;  // times offered every this many minutes
	private const TEST_NOW = '';   // demo only, e.g. '2026-11-17 19:15'; keep '' in production

	// Times that can still be chosen today: at least MIN_LEAD ahead, not before opening, before closing
	private function slots(): array {
		$now = new \DateTimeImmutable(self::TEST_NOW !== '' ? self::TEST_NOW : 'now');
		$hours = self::HOURS[(int)$now->format('N')] ?? null;

		if (!$hours) {
			return [];
		}

		[$oh, $om] = array_map('intval', explode(':', $hours[0]));
		[$ch, $cm] = array_map('intval', explode(':', $hours[1]));

		$midnight = $now->setTime(0, 0)->getTimestamp();
		$earliest = max($now->getTimestamp() + self::MIN_LEAD * 60, $now->setTime($oh, $om)->getTimestamp());
		$first = (int)(ceil(ceil(($earliest - $midnight) / 60) / self::SLOT_STEP) * self::SLOT_STEP);

		$slots = [];

		for ($m = $first; $m < $ch * 60 + $cm; $m += self::SLOT_STEP) {
			$slots[] = sprintf('%02d:%02d', intdiv($m, 60), $m % 60);
		}

		return $slots;
	}

	// '' = valid (no time chosen, or chosen time still allowed), otherwise an error message
	private function error(): string {
		$time = $this->session->data['atelier_collection_time'] ?? '';

		if ($time === '' || in_array($time, $this->slots(), true)) {
			return '';
		}

		return 'Collection at ' . $time . ' is no longer possible (it must be at least 1 hour from now and before closing). Please choose another time.';
	}

	// Checkout page: add the time picker above Payment Method
	public function checkout(string &$route, array &$args, string &$output): void {
		$chosen = $this->session->data['atelier_collection_time'] ?? '';
		$language = $this->config->get('config_language');

		$options = '<option value="">As soon as possible</option>';

		foreach ($this->slots() as $slot) {
			$options .= '<option value="' . $slot . '"' . ($slot === $chosen ? ' selected' : '') . '>' . $slot . '</option>';
		}

		$html = '<div id="checkout-collection-time" class="mb-4"><fieldset><legend>Collection time</legend>'
			. '<select id="input-collection-time" class="form-select">' . $options . '</select>'
			. '<div class="form-text">A chosen time must be at least 1 hour from now and before closing.</div>'
			. '<div id="collection-time-message" class="form-text"></div></fieldset></div>'
			. '<script type="text/javascript">$("#input-collection-time").on("change", function() {'
			. '$.post("index.php?route=extension/atelier/event/collection_time.save&language=' . $language . '", {time: this.value}, function(json) {'
			. '$("#collection-time-message").text(json.error || json.success).toggleClass("text-danger", !!json.error);'
			. '$("#checkout-confirm").load("index.php?route=checkout/confirm.confirm&language=' . $language . '");'
			. '}, "json"); });</script>';

		$output = str_replace('<div id="checkout-payment-method"', $html . '<div id="checkout-payment-method"', $output);
	}

	// Called by the picker: store the chosen time if it is allowed
	public function save(): void {
		$time = (string)($this->request->post['time'] ?? '');
		$json = [];

		if ($time !== '' && !in_array($time, $this->slots(), true)) {
			unset($this->session->data['atelier_collection_time']);
			$json['error'] = 'That time is not available. Choose a time at least 1 hour from now and before closing.';
		} else {
			$this->session->data['atelier_collection_time'] = $time;
			$json['success'] = $time === '' ? 'Collection: as soon as possible' : 'Collection at ' . $time;
		}

		$this->response->addHeader('Content-Type: application/json');
		$this->response->setOutput(json_encode($json));
	}

	// Confirm step: if the chosen time has expired, show why and hide the payment button
	public function confirm(string &$route, array &$args, string &$output): void {
		$error = $this->error();

		if ($error) {
			$output = str_replace('<div id="checkout-payment">', '<div class="alert alert-warning">' . htmlspecialchars($error) . '</div><div id="checkout-payment" style="display:none">', $output);
		}
	}

	// Order: write the chosen time at the top of the order comment
	public function order(string &$route, array &$args): void {
		$time = $this->session->data['atelier_collection_time'] ?? '';

		if ($time !== '' && isset($args[0]) && is_array($args[0])) {
			$args[0]['comment'] = trim('Collection at ' . $time . "\n\n" . ($args[0]['comment'] ?? ''));
		}
	}

	// Any payment method's confirm: refuse if the chosen time is no longer allowed
	public function guard(string &$route, array &$args): void {
		if ($this->error()) {
			$route = 'extension/atelier/event/collection_time.blocked';
		}
	}

	public function blocked(): void {
		$this->response->addHeader('Content-Type: application/json');
		$this->response->setOutput(json_encode(['error' => $this->error()]));
	}
}
