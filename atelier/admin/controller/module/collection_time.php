<?php
namespace Opencart\Admin\Controller\Extension\Atelier\Module;
class CollectionTime extends \Opencart\System\Engine\Controller {
	private const EVENTS = [
		'catalog/view/checkout/checkout/after'                => 'extension/atelier/event/collection_time.checkout',
		'catalog/view/checkout/confirm/after'                 => 'extension/atelier/event/collection_time.confirm',
		'catalog/model/checkout/order.addOrder/before'        => 'extension/atelier/event/collection_time.order',
		'catalog/controller/extension/*/payment/*.confirm/before' => 'extension/atelier/event/collection_time.guard'
	];

	public function index(): void {
		$this->response->redirect($this->url->link('marketplace/extension', 'user_token=' . $this->session->data['user_token'] . '&type=module'));
	}

	public function install(): void {
		$this->load->model('setting/event');
		$this->model_setting_event->deleteEventByCode('atelier_collection_time');

		foreach (self::EVENTS as $trigger => $action) {
			$this->model_setting_event->addEvent([
				'code'        => 'atelier_collection_time',
				'description' => 'Atelier collection time',
				'trigger'     => $trigger,
				'action'      => $action,
				'status'      => 1,
				'sort_order'  => 0
			]);
		}
	}

	public function uninstall(): void {
		$this->load->model('setting/event');
		$this->model_setting_event->deleteEventByCode('atelier_collection_time');
	}
}
