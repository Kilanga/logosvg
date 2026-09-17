<?php
if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * Shortcode [tshirt_ia_designer] : formulaire de création et aperçu.
 */
class TSIA_Shortcode {

	const STYLES = array(
		'illustration' => 'Illustration',
		'logo'         => 'Logo',
		'mascotte'     => 'Mascotte',
		'badge'        => 'Badge vintage',
	);

	const SHIRTS = array(
		'#f7f7f5' => 'Blanc',
		'#1c1c1f' => 'Noir',
		'#8e9296' => 'Gris chiné',
		'#1f2a44' => 'Marine',
	);

	public static function init() {
		add_shortcode( 'tshirt_ia_designer', array( __CLASS__, 'render' ) );
	}

	private static function enqueue() {
		wp_enqueue_style( 'tsia-designer', TSIA_URL . 'assets/designer.css', array(), TSIA_VERSION );
		wp_enqueue_script( 'tsia-designer', TSIA_URL . 'assets/designer.js', array(), TSIA_VERSION, array( 'in_footer' => true ) );
		wp_add_inline_script(
			'tsia-designer',
			'window.TSIA_CONFIG = ' . wp_json_encode(
				array(
					'ajaxUrl' => admin_url( 'admin-ajax.php' ),
					'nonce'   => wp_create_nonce( 'tsia_designer' ),
				)
			) . ';',
			'before'
		);
		if ( '' !== TSIA_Settings::get( 'turnstile_site_key' ) ) {
			wp_enqueue_script(
				'cf-turnstile',
				'https://challenges.cloudflare.com/turnstile/v0/api.js',
				array(),
				null, // phpcs:ignore WordPress.WP.EnqueuedResourceParameters.MissingVersion
				array( 'strategy' => 'defer', 'in_footer' => true )
			);
		}
	}

	public static function render() {
		wp_enqueue_style( 'tsia-designer', TSIA_URL . 'assets/designer.css', array(), TSIA_VERSION );

		if ( ! is_user_logged_in() ) {
			return sprintf(
				'<div class="tsia tsia--guest"><p>Créez votre design en quelques mots, prêt pour l\'impression. <a href="%s">Connectez-vous</a> pour commencer.</p></div>',
				esc_url( wp_login_url( get_permalink() ) )
			);
		}

		self::enqueue();
		$uid       = wp_unique_id( 'tsia-' );
		$site_key  = (string) TSIA_Settings::get( 'turnstile_site_key' );
		$shirt_def = array_key_first( self::SHIRTS );

		ob_start();
		?>
		<div class="tsia" data-tsia>
			<form class="tsia-form" data-tsia-form novalidate>
				<div class="tsia-field">
					<label for="<?php echo esc_attr( $uid ); ?>-prompt">Décrivez votre design</label>
					<textarea id="<?php echo esc_attr( $uid ); ?>-prompt" name="prompt" rows="4" minlength="3" maxlength="300" required
						placeholder="Un renard qui fait du skate au coucher du soleil"
						aria-describedby="<?php echo esc_attr( $uid ); ?>-count"></textarea>
					<p class="tsia-hint" id="<?php echo esc_attr( $uid ); ?>-count" data-tsia-count>0 / 300</p>
				</div>

				<fieldset class="tsia-field">
					<legend>Style</legend>
					<div class="tsia-chips">
						<?php foreach ( self::STYLES as $value => $label ) : ?>
							<label class="tsia-chip">
								<input type="radio" name="style" value="<?php echo esc_attr( $value ); ?>" <?php checked( 'illustration', $value ); ?> />
								<span><?php echo esc_html( $label ); ?></span>
							</label>
						<?php endforeach; ?>
					</div>
				</fieldset>

				<div class="tsia-field">
					<label for="<?php echo esc_attr( $uid ); ?>-colors">Nombre de couleurs</label>
					<div class="tsia-range">
						<input id="<?php echo esc_attr( $uid ); ?>-colors" type="range" name="colors" min="1" max="6" value="3" step="1" />
						<output for="<?php echo esc_attr( $uid ); ?>-colors" data-tsia-colors-out>3 couleurs</output>
					</div>
					<p class="tsia-hint">Moins de couleurs, c'est moins d'écrans en sérigraphie et une impression moins chère.</p>
				</div>

				<div class="tsia-field">
					<label class="tsia-check">
						<input type="checkbox" name="remove_background" value="1" checked />
						<span>Retirer le fond blanc</span>
					</label>
				</div>

				<?php if ( '' !== $site_key ) : ?>
					<div class="cf-turnstile" data-sitekey="<?php echo esc_attr( $site_key ); ?>" data-language="fr"></div>
				<?php endif; ?>

				<button type="submit" class="tsia-button" data-tsia-submit>Créer le design</button>
				<p class="tsia-status" data-tsia-status role="status" aria-live="polite"></p>
			</form>

			<section class="tsia-result" data-tsia-result hidden aria-labelledby="<?php echo esc_attr( $uid ); ?>-result-title">
				<div class="tsia-result__head">
					<h3 id="<?php echo esc_attr( $uid ); ?>-result-title" tabindex="-1">Votre design</h3>
					<div class="tsia-toggle" role="group" aria-label="Affichage">
						<button type="button" data-tsia-view="shirt" aria-pressed="true">Sur le t-shirt</button>
						<button type="button" data-tsia-view="compare" aria-pressed="false">Image et vecteur</button>
					</div>
				</div>

				<div class="tsia-stage" data-tsia-panel="shirt">
					<svg class="tsia-shirt" viewBox="0 0 400 392" role="img" aria-label="Aperçu du design sur un t-shirt" style="--tsia-shirt: <?php echo esc_attr( $shirt_def ); ?>" data-tsia-shirt>
						<path class="tsia-shirt__body" d="M136 20 L172 8 Q200 44 228 8 L264 20 L384 80 L348 154 L306 136 L306 382 L94 382 L94 136 L52 154 L16 80 Z" />
						<path class="tsia-shirt__collar" d="M172 8 Q200 44 228 8" />
						<image data-tsia-print x="122" y="84" width="156" height="156" preserveAspectRatio="xMidYMid meet" />
					</svg>
					<div class="tsia-swatches" role="group" aria-label="Couleur du t-shirt">
						<?php foreach ( self::SHIRTS as $hex => $label ) : ?>
							<button type="button" class="tsia-swatch" data-tsia-shirt-color="<?php echo esc_attr( $hex ); ?>"
								style="--tsia-swatch: <?php echo esc_attr( $hex ); ?>"
								aria-pressed="<?php echo $hex === $shirt_def ? 'true' : 'false'; ?>">
								<span class="tsia-visually-hidden"><?php echo esc_html( $label ); ?></span>
							</button>
						<?php endforeach; ?>
					</div>
				</div>

				<div class="tsia-stage" data-tsia-panel="compare" hidden>
					<div class="tsia-compare" data-tsia-compare>
						<figure>
							<div class="tsia-frame"><img data-tsia-png alt="Image générée, avant vectorisation" /></div>
							<figcaption>Image (pixels)</figcaption>
						</figure>
						<figure>
							<div class="tsia-frame"><img data-tsia-svg alt="Design vectorisé" /></div>
							<figcaption>Vecteur (SVG)</figcaption>
						</figure>
					</div>
					<button type="button" class="tsia-link" data-tsia-zoom aria-pressed="false">Zoomer ×4</button>
				</div>

				<div class="tsia-inks">
					<p class="tsia-inks__title" data-tsia-inks-title></p>
					<ul class="tsia-inks__list" data-tsia-inks></ul>
				</div>

				<ul class="tsia-warnings" data-tsia-warnings hidden></ul>

				<div class="tsia-actions">
					<a class="tsia-button" data-tsia-download download>Télécharger le SVG</a>
					<button type="button" class="tsia-link" data-tsia-again>Créer une variante</button>
				</div>
			</section>
		</div>
		<?php
		return ob_get_clean();
	}
}
