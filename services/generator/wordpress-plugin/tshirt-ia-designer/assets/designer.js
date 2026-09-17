/* T-shirt IA Designer : envoi de la demande, suivi, affichage du résultat. */
(function () {
	'use strict';

	var config = window.TSIA_CONFIG;
	if (!config) return;

	var POLL_MS = 2000;
	var MAX_WAIT_MS = 5 * 60 * 1000;

	function plural(n, one, many) {
		return n + ' ' + (n > 1 ? many : one);
	}

	function init(root) {
		var form = root.querySelector('[data-tsia-form]');
		var textarea = form.querySelector('textarea[name="prompt"]');
		var counter = root.querySelector('[data-tsia-count]');
		var range = form.querySelector('input[name="colors"]');
		var rangeOut = root.querySelector('[data-tsia-colors-out]');
		var submit = root.querySelector('[data-tsia-submit]');
		var status = root.querySelector('[data-tsia-status]');
		var result = root.querySelector('[data-tsia-result]');
		var title = result.querySelector('h3');
		var shirt = root.querySelector('[data-tsia-shirt]');
		var print = root.querySelector('[data-tsia-print]');
		var png = root.querySelector('[data-tsia-png]');
		var svg = root.querySelector('[data-tsia-svg]');
		var compare = root.querySelector('[data-tsia-compare]');
		var zoom = root.querySelector('[data-tsia-zoom]');
		var inksTitle = root.querySelector('[data-tsia-inks-title]');
		var inks = root.querySelector('[data-tsia-inks]');
		var warnings = root.querySelector('[data-tsia-warnings]');
		var download = root.querySelector('[data-tsia-download]');
		var again = root.querySelector('[data-tsia-again]');
		var busy = false;

		function setStatus(text, isError) {
			status.textContent = text || '';
			status.classList.toggle('is-error', !!isError);
		}

		function setBusy(value) {
			busy = value;
			submit.disabled = value;
			submit.textContent = value ? 'Création en cours…' : 'Créer le design';
		}

		function resetTurnstile() {
			var widget = form.querySelector('.cf-turnstile');
			if (widget && window.turnstile) window.turnstile.reset(widget);
		}

		function updateCount() {
			counter.textContent = textarea.value.length + ' / 300';
		}

		function updateColors() {
			rangeOut.textContent = plural(Number(range.value), 'couleur', 'couleurs');
		}

		textarea.addEventListener('input', updateCount);
		range.addEventListener('input', updateColors);
		updateCount();
		updateColors();

		function request(url, options) {
			return fetch(url, Object.assign({ credentials: 'same-origin' }, options)).then(function (res) {
				return res.json().catch(function () {
					return { success: false, data: { message: 'Réponse illisible du site (code ' + res.status + ').' } };
				});
			});
		}

		form.addEventListener('submit', function (event) {
			event.preventDefault();
			if (busy) return;

			var prompt = textarea.value.trim();
			if (prompt.length < 3) {
				setStatus('Décrivez votre design en au moins 3 caractères.', true);
				textarea.focus();
				return;
			}

			var data = new FormData(form);
			data.set('remove_background', form.querySelector('input[name="remove_background"]').checked ? '1' : '0');
			data.append('action', 'tsia_start');
			data.append('nonce', config.nonce);

			setBusy(true);
			setStatus('Envoi de la demande…');

			request(config.ajaxUrl, { method: 'POST', body: data })
				.then(function (json) {
					resetTurnstile();
					if (!json.success) throw new Error(json.data && json.data.message);
					var left = json.data.remaining;
					if (typeof left === 'number') {
						setStatus('Demande reçue. ' + plural(left, 'création restante', 'créations restantes') + " aujourd'hui.");
					}
					poll(json.data.job_id, Date.now());
				})
				.catch(function (err) {
					setBusy(false);
					setStatus(err.message || 'La demande n\'a pas pu être envoyée. Vérifiez votre connexion.', true);
				});
		});

		function poll(jobId, startedAt) {
			if (Date.now() - startedAt > MAX_WAIT_MS) {
				setBusy(false);
				setStatus('La création prend plus de temps que prévu. Rechargez la page dans quelques minutes.', true);
				return;
			}
			var url = config.ajaxUrl + '?action=tsia_status&nonce=' + encodeURIComponent(config.nonce) +
				'&job_id=' + encodeURIComponent(jobId);

			request(url, { method: 'GET' })
				.then(function (json) {
					if (!json.success) throw new Error(json.data && json.data.message);
					var job = json.data;
					if (job.status === 'done') {
						setBusy(false);
						setStatus('Design prêt.');
						render(job);
						return;
					}
					if (job.status === 'error') {
						throw new Error(job.error || 'La création a échoué. Reformulez votre idée et relancez.');
					}
					setStatus(job.status === 'queued' && job.position > 1
						? 'En attente : ' + (job.position - 1) + ' création(s) avant la vôtre.'
						: 'Création et vectorisation en cours, comptez 20 à 60 secondes…');
					window.setTimeout(function () { poll(jobId, startedAt); }, POLL_MS);
				})
				.catch(function (err) {
					setBusy(false);
					setStatus(err.message || 'Le suivi de la création a été interrompu.', true);
				});
		}

		function render(job) {
			var files = job.files;
			var res = job.result || {};
			var bust = '?v=' + job.job_id.slice(0, 8);

			print.setAttribute('href', files.svg + bust);
			png.src = files.png + bust;
			svg.src = files.svg + bust;
			download.href = files.svg;
			download.setAttribute('download', 'design-' + job.job_id.slice(0, 8) + '.svg');

			var count = res.inks || 0;
			inksTitle.textContent = plural(count, 'encre', 'encres') + ', soit ' +
				plural(count, 'écran', 'écrans') + ' en sérigraphie';
			inks.innerHTML = '';
			(res.palette || []).forEach(function (ink) {
				var li = document.createElement('li');
				var chip = document.createElement('span');
				chip.className = 'tsia-ink';
				chip.style.setProperty('--tsia-ink-color', ink.hex);
				li.appendChild(chip);
				li.appendChild(document.createTextNode(ink.hex.toUpperCase()));
				inks.appendChild(li);
			});

			warnings.innerHTML = '';
			(res.warnings || []).forEach(function (text) {
				var li = document.createElement('li');
				li.textContent = text;
				warnings.appendChild(li);
			});
			warnings.hidden = !(res.warnings && res.warnings.length);

			result.hidden = false;
			title.focus({ preventScroll: true });
			result.scrollIntoView({ behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'start' });
		}

		root.querySelectorAll('[data-tsia-view]').forEach(function (button) {
			button.addEventListener('click', function () {
				var view = button.getAttribute('data-tsia-view');
				root.querySelectorAll('[data-tsia-view]').forEach(function (b) {
					b.setAttribute('aria-pressed', String(b === button));
				});
				root.querySelectorAll('[data-tsia-panel]').forEach(function (panel) {
					panel.hidden = panel.getAttribute('data-tsia-panel') !== view;
				});
			});
		});

		root.querySelectorAll('[data-tsia-shirt-color]').forEach(function (button) {
			button.addEventListener('click', function () {
				shirt.style.setProperty('--tsia-shirt', button.getAttribute('data-tsia-shirt-color'));
				root.querySelectorAll('[data-tsia-shirt-color]').forEach(function (b) {
					b.setAttribute('aria-pressed', String(b === button));
				});
			});
		});

		zoom.addEventListener('click', function () {
			var on = !compare.classList.contains('is-zoomed');
			compare.classList.toggle('is-zoomed', on);
			zoom.setAttribute('aria-pressed', String(on));
			zoom.textContent = on ? 'Revenir à la taille normale' : 'Zoomer ×4';
		});

		again.addEventListener('click', function () {
			textarea.focus();
			form.scrollIntoView({ block: 'start' });
		});
	}

	function start() {
		document.querySelectorAll('[data-tsia]').forEach(init);
	}

	if (document.readyState === 'loading') {
		document.addEventListener('DOMContentLoaded', start);
	} else {
		start();
	}
})();
