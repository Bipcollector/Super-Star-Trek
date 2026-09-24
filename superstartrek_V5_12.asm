; ===============================================
; SUPER STAR TREK - Memo-1 / Minitel
; Ver. V5.12
; ===============================================
; Version assembleur 6502 complète
; Compatible VASM oldstyle
; EEPROM 28C64 (8 Ko)
; Par BipCollector & Claude - 2026
; Optimisation du code V3.48 par Lovable
; Melt-Banana - Cracked Plaster Cast
; ===============================================

    .org $A000
    .byte "STARTREK"          ; 8 octets signature

; -----------------------------------------------
; DÉFINITIONS MATÉRIELLES
; -----------------------------------------------
ACIA_DATA    = $9000
ACIA_STATUS  = $9001
VIA_T1CL     = $8004
VIA_T1CH     = $8005
VIA_ACR      = $800B

; -----------------------------------------------
; ADRESSES ROM
; -----------------------------------------------
GET_KEY      = $E11D

; -----------------------------------------------
; CODES MINITEL
; -----------------------------------------------
CLS          = $0C            ; Effacer l'écran (Form Feed)
CR           = $0D            ; Retour chariot
LF           = $0A            ; Saut de ligne

; -----------------------------------------------
; VARIABLES PAGE ZÉRO
; -----------------------------------------------
string_ptr   = $0012          ; Pointeur chaîne (2 octets)

; Position et état du vaisseau
Q1           = $0020          ; Quadrant X (1-8)
Q2           = $0021          ; Quadrant Y (1-8)
S1           = $0022          ; Secteur X (1-8)
S2           = $0023          ; Secteur Y (1-8)
E            = $0024          ; Énergie (16-bit lo)
E_hi         = $0025          ; Énergie (16-bit hi)
P            = $0026          ; Torpilles photoniques
S            = $0027          ; Boucliers (16-bit lo)
S_hi         = $0028          ; Boucliers (16-bit hi)

; Statistiques mission
K9           = $0029          ; Klingons total galaxie
K3           = $002A          ; Klingons quadrant actuel
B9           = $002B          ; Bases stellaires total
B3           = $002C          ; Bases quadrant actuel
STARS        = $002D          ; Étoiles quadrant actuel

; Temps
T            = $002E          ; Date stellaire actuelle (16-bit lo)
T_hi         = $002F          ; Date stellaire actuelle (16-bit hi)
T0           = $0030          ; Date stellaire départ (16-bit lo)
T0_hi        = $0031          ; Date stellaire départ (16-bit hi)
T9           = $0032          ; Jours disponibles mission

; Flags
docked_flag  = $0033          ; 1=amarré à base
first_turn   = $0034          ; 1=premier tour

; Systèmes endommagés (0=OK, >0=endommagé)
DMG_WARP     = $0035          ; Moteurs Warp
DMG_LRS      = $0036          ; Scanner longue portée
DMG_SRS      = $0037          ; Scanner courte portée
DMG_PHASERS  = $0038          ; Phasers
DMG_TORPS    = $0039          ; Torpilles
DMG_SHIELDS  = $003A          ; Boucliers
DMG_COMPUTER = $003B          ; Ordinateur
DMG_DAMAGE   = $003C          ; Contrôle dommages

; Données Klingons (3 max, 3 octets chacun : X, Y, Boucliers)
K_data       = $0040          ; 9 octets ($0040-$0048)

; Position base stellaire dans quadrant
B_pos        = $004A          ; X, Y (2 octets)

; Positions étoiles (max 8)
S_data       = $004C          ; 16 octets (8 × 2)

; Variables temporaires
temp1        = $005C
temp2        = $005D
temp3        = $005E
temp4        = $005F
temp5        = $0060
temp6        = $0061
temp7        = $0062
temp8        = $0063
temp9        = $0079
temp10       = $007C

; Buffer de saisie
input_buf    = $0064          ; 16 octets
input_len    = $0074

; Générateur aléatoire
rnd_seed     = $0075          ; 2 octets
rnd_seed_hi  = $0076

; Navigation
course       = $0077          ; Direction (1-9)
warp_factor  = $0078          ; Vitesse (0-9)

; Variables scanner LRS
lrs_x_save   = $007A
lrs_y_save   = $007B

; Anti-veille Minitel (keep-alive)
ka_counter   = $007D          ; 2 octets compteur keep-alive (lo, hi)
ka_counter_hi = $007E
ka_damage_total = $007F       ; Dégâts totaux reçus pendant attaque Klingons

; -----------------------------------------------
; GRILLES EN RAM HAUTE
; -----------------------------------------------
quadrant     = $0200          ; 64 octets - grille quadrant (0=vide,1=K,2=B,3=*,4=E)
galaxy       = $0240          ; 64 octets - données galaxie (K×100+B×10+S)
z_grid       = $0280          ; 64 octets - exploration (0=inconnu,1=exploré)

; ===============================================
; POINT D'ENTRÉE PRINCIPAL
; DIR EN GREY - AGITATED SCREAMS OF MAGGOS -UNPLUGGED-
; ===============================================
start:
    jsr init_game
    jsr show_intro
    jsr show_mission
    jsr wait_key_press
    jsr enter_quadrant

main_loop:
    jsr show_short_range_scan
    jsr check_docking
    cmp #1
    bne ml_continue
    jsr show_short_range_scan

ml_continue:
    jsr show_commands
    jsr get_command
    jsr execute_command

    lda docked_flag
    bne skip_attack
    jsr klingon_attack

skip_attack:
    jsr check_game_over
    jmp main_loop

; ===============================================
; INITIALISATION DU JEU
; DIR EN GREY - Bottom of the death valley
; ===============================================
init_game:
    ; Seed aléatoire depuis VIA T1 (libre-running)
    ; NE PAS réinitialiser si seed déjà non-nulle
    ; (cas nouvelle partie : seed continue)
    lda rnd_seed
    ora rnd_seed_hi
    bne rnd_seed_ok     ; seed déjà active → on la garde

    ; Premier boot : lire T1 counter (valeur imprévisible)
    lda VIA_T1CL
    eor #$5A
    sta rnd_seed
    lda VIA_T1CH
    eor #$A5
    sta rnd_seed_hi

    ; Si toujours zéro (T1 pas lancé), valeur par défaut
    lda rnd_seed
    ora rnd_seed_hi
    bne rnd_seed_ok
    lda #$3F
    sta rnd_seed
    lda #$72
    sta rnd_seed_hi

rnd_seed_ok:
    ; Énergie = 3000
    lda #<3000
    sta E
    lda #>3000
    sta E_hi

    ; Torpilles = 10
    lda #10
    sta P

    ; Boucliers = 0
    lda #0
    sta S
    sta S_hi

    ; Date stellaire commence à 2265
    lda #<2265
    sta T
    lda #>2265
    sta T_hi

    lda T
    sta T0
    lda T_hi
    sta T0_hi

    ; Jours mission (25-40)
    jsr random
    and #$0F
    clc
    adc #25
    sta T9

    ; Effacer systèmes endommagés
    lda #0
    sta DMG_WARP
    sta DMG_LRS
    sta DMG_SRS
    sta DMG_PHASERS
    sta DMG_TORPS
    sta DMG_SHIELDS
    sta DMG_COMPUTER
    sta DMG_DAMAGE

    ; Position Enterprise aléatoire (1-8 pour chaque coordonnée)
    jsr random
    and #$07
    clc
    adc #1
    sta Q1

    jsr random
    and #$07
    clc
    adc #1
    sta Q2

    jsr random
    and #$07
    clc
    adc #1
    sta S1

    jsr random
    and #$07
    clc
    adc #1
    sta S2

    ; Initialiser totaux
    lda #0
    sta K9
    sta B9

    ; Effacer tableau galaxy (64 octets)
    lda #<galaxy
    sta temp1
    lda #>galaxy
    sta temp2
    ldy #0
    lda #0
clear_galaxy:
    sta (temp1),y
    iny
    cpy #64
    bne clear_galaxy

    ; Générer galaxie V5.02 : encodage bit-packing
    ; Format : (K<<5) | (B<<4) | S
    ; K=Klingons (bits 7-5), B=Base (bit 4), S=Etoiles (bits 3-0)
    ; Valeur max = 3*32+16+8=120, jamais > 255
    ; Phase 1 : étoiles seulement dans tous les quadrants
    ldx #0
gen_galaxy_loop:
    ; Étoiles (1-8)
    jsr random
    and #$07
    clc
    adc #1              ; 1-8 étoiles, stocké dans bits 3-0

    ; Stocker dans galaxy[]
    pha
    lda #<galaxy
    sta temp5
    lda #>galaxy
    sta temp6
    txa
    tay
    pla
    sta (temp5),y

    ; Effacer grille exploration
    lda #<z_grid
    sta temp5
    lda #>z_grid
    sta temp6
    txa
    tay
    lda #0
    sta (temp5),y

    inx
    cpx #64
    beq gen_phase2
    jmp gen_galaxy_loop

gen_phase2:
    ; Phase 2 : placer exactement 1 base dans un quadrant aléatoire
    lda #1
    sta B9
    jsr random
    and #$3F            ; index 0-63
    tax
    lda galaxy,x
    ora #$10            ; Mettre bit 4 = Base (au lieu de adc #10)
    sta galaxy,x

    ; Phase 3 : distribuer exactement 20 Klingons, max 3 par quadrant
    lda #20
    sta temp3           ; compteur Klingons restants

gen_k_loop:
    lda temp3
    beq gen_k_done

    ; Choisir quadrant aléatoire
    jsr random
    and #$3F            ; index 0-63
    tax

    ; Extraire Klingons actuels (bits 7-5)
    lda galaxy,x
    sta temp4
    lsr
    lsr
    lsr
    lsr
    lsr             ; A = K (0-3)
    sta temp5

gen_k_check_max:
    ; Max 3 Klingons par quadrant
    lda temp5
    cmp #3
    bcs gen_k_loop      ; déjà 3, réessayer

    ; Ajouter 1 Klingon (bit-field +32)
    lda galaxy,x
    clc
    adc #$20            ; +32 = +1 Klingon dans bits 7-5
    sta galaxy,x
    dec temp3
    jmp gen_k_loop

gen_k_done:
    lda #20
    sta K9

gen_galaxy_done:

init_flags:
    lda #1
    sta first_turn
    lda #0
    sta docked_flag
    ; Initialiser compteur anti-veille
    lda #<500
    sta ka_counter
    lda #>500
    sta ka_counter_hi
    rts

; ===============================================
; ENTRER DANS QUADRANT
; DIR EN GREY - Unraveling (Unplugged Ver.)
; ===============================================
enter_quadrant:
    ; Index = (Q2-1) × 8 + (Q1-1)
    lda Q2
    sec
    sbc #1
    asl
    asl
    asl
    sta temp1
    lda Q1
    sec
    sbc #1
    clc
    adc temp1
    tax

    ; Marquer comme exploré
    lda #1
    sta z_grid,x

    ; Lire données quadrant
    stx temp9
    lda #<galaxy
    sta temp7
    lda #>galaxy
    sta temp8
    ldx temp9
    txa
    tay
    lda (temp7),y
    sta temp1

    ; Extraire K3 (bits 7-5 → K = val >> 5)
    lda #0
    sta K3
    lda temp1
    lsr
    lsr
    lsr
    lsr
    lsr             ; A = nombre de Klingons
    sta K3

eq_get_b3:
    ; Extraire B3 (bit 4 → B = (val >> 4) & 1)
    lda temp1
    lsr
    lsr
    lsr
    lsr             ; bit 4 → bit 0
    and #$01
    sta B3

eq_get_s3:
    ; Extraire S (bits 3-0)
    lda temp1
    and #$0F
    sta STARS

    ; Effacer grille quadrant
    ldx #0
    lda #0
eq_clear_grid:
    sta quadrant,x
    inx
    cpx #64
    bne eq_clear_grid

    ; Effacer données Klingons
    ldy #0
    lda #0
eq_clear_k:
    sta $0040,y
    iny
    cpy #9
    bne eq_clear_k

    ; Placer Klingons
    lda K3
    beq eq_place_base_skip_k
    sta temp3
    ldy #0

eq_place_k_simple:
    jsr find_empty_sector

    lda temp1
    sta $0040,y
    iny
    lda temp2
    sta $0040,y
    iny

    ; Boucliers aléatoires (100-227)
    jsr random
    and #$7F
    clc
    adc #100
    sta $0040,y
    iny

    ; Marquer dans grille
    lda temp2
    sec
    sbc #1
    asl
    asl
    asl
    sta temp4
    lda temp1
    sec
    sbc #1
    clc
    adc temp4
    tax
    lda #1
    sta quadrant,x

    dec temp3
    bne eq_place_k_simple

eq_place_base_skip_k:
    ; Placer Enterprise - vérifier que la case est libre
    lda S2
    sec
    sbc #1
    asl
    asl
    asl
    sta temp4
    lda S1
    sec
    sbc #1
    clc
    adc temp4
    tax
    
    ; Case libre ?
    lda quadrant,x
    beq eq_place_enterprise  ; 0 = vide, OK
    
    ; Case occupée (Klingon ou étoile) → chercher case vide
    jsr find_empty_sector
    lda temp1
    sta S1              ; Mettre à jour S1
    lda temp2
    sta S2              ; Mettre à jour S2
    
    ; Recalculer index
    lda S2
    sec
    sbc #1
    asl
    asl
    asl
    sta temp4
    lda S1
    sec
    sbc #1
    clc
    adc temp4
    tax

eq_place_enterprise:
    lda #4
    sta quadrant,x

eq_place_base:
    ; Placer base stellaire
    lda B3
    beq eq_place_stars

    jsr find_empty_sector
    lda temp1
    sta B_pos
    lda temp2
    sta B_pos+1

    lda temp2
    sec
    sbc #1
    asl
    asl
    asl
    sta temp4
    lda temp1
    sec
    sbc #1
    clc
    adc temp4
    tax
    lda #2
    sta quadrant,x

eq_place_stars:
    lda STARS
    beq eq_done
    sta temp3
    ldx #0

eq_place_s_loop:
    jsr find_empty_sector

    lda temp1
    sta S_data,x
    inx
    lda temp2
    sta S_data,x
    inx

    lda temp2
    sec
    sbc #1
    asl
    asl
    asl
    sta temp4
    lda temp1
    sec
    sbc #1
    clc
    adc temp4
    tay
    lda #3
    sta quadrant,y

    dec temp3
    bne eq_place_s_loop

eq_done:
    rts

; ===============================================
; TROUVER SECTEUR VIDE
; HANABIE - NEET GAME
; ===============================================
find_empty_sector:
fes_loop:
    jsr random
    and #$07
    clc
    adc #1
    sta temp1

    jsr random
    and #$07
    clc
    adc #1
    sta temp2

    lda temp2
    sec
    sbc #1
    asl
    asl
    asl
    sta temp4
    lda temp1
    sec
    sbc #1
    clc
    adc temp4
    tax

    lda quadrant,x
    bne fes_loop
    rts

; ===============================================
; AFFICHER SYMBOLE CELLULE GRILLE
; Entrée : A = contenu (0=vide,1=K,2=B,3=*,4=E)
; ===============================================
display_cell:
    cmp #1
    bcc dc_empty
    beq dc_klingon
    cmp #2
    beq dc_base
    cmp #3
    beq dc_star
    ; 4 = Enterprise
    lda #'E'
    jmp print_char
dc_empty:
    lda #'.'
    jmp print_char
dc_klingon:
    lda #'K'
    jmp print_char
dc_base:
    lda #'B'
    jmp print_char
dc_star:
    lda #'*'
    jmp print_char

; ===============================================
; AFFICHER INTRO
; zero[Hz] - skeles me dop HEADz
; ===============================================
show_intro:
    lda #CLS
    jsr print_char
	
	lda #<msg_tit
    sta string_ptr
    lda #>msg_tit
    sta string_ptr+1
    jsr print_string

    lda #<msg_intro
    sta string_ptr
    lda #>msg_intro
    sta string_ptr+1
    jsr print_string

    lda #<msg_intro1
    sta string_ptr
    lda #>msg_intro1
    sta string_ptr+1
    jmp print_string

; ===============================================
; AFFICHER MISSION
; The THIRTEEN - WHITE DUST
; ===============================================
show_mission:
    lda #<msg_mission1
    sta string_ptr
    lda #>msg_mission1
    sta string_ptr+1
    jsr print_string

    lda K9
    jsr print_num

    lda #<msg_mission2
    sta string_ptr
    lda #>msg_mission2
    sta string_ptr+1
    jsr print_string

    ; Date limite (T0 + T9) en 16 bits
    lda T0
    clc
    adc T9
    sta temp1
    lda T0_hi
    adc #0
    sta temp2
    jsr print_16bit_from_temp

    lda #<msg_mission3
    sta string_ptr
    lda #>msg_mission3
    sta string_ptr+1
    jsr print_string

    lda T9
    jsr print_num

    lda #<msg_mission4
    sta string_ptr
    lda #>msg_mission4
    sta string_ptr+1
    jsr print_string

    lda B9
    jsr print_num

    lda #<msg_mission5
    sta string_ptr
    lda #>msg_mission5
    sta string_ptr+1
    jmp print_string

; ===============================================
; BORDURES SCANNER (haut et bas identiques)
; ===============================================
print_srs_border:
    lda #'+'
    jsr print_char
    ldx #0
psb_loop:
    lda #'-'
    jsr print_char
    inx
    cpx #18
    bne psb_loop
    lda #'+'
    jsr print_char
    jmp print_crlf

; ===============================================
; AFFICHER LIGNE DE GRILLE (8 colonnes)
; Entrée : temp7 = numéro de ligne (0-7)
; Sortie : bordures |  et symboles affichés
; ===============================================
print_grid_row:
    lda #'|'
    jsr print_char

    ; Numéro de ligne (1-8)
    lda temp7
    clc
    adc #'1'
    jsr print_char

    lda #' '
    jsr print_char

    lda #0
    sta temp6

pgr_col_loop:
    lda temp7
    asl
    asl
    asl
    clc
    adc temp6
    tax

    lda quadrant,x
    jsr display_cell

    lda #' '
    jsr print_char

    inc temp6
    lda temp6
    cmp #8
    bne pgr_col_loop

    lda #'|'
    jmp print_char

; ===============================================
; SCANNER COURTE PORTÉE
; The THIRTEEN - Aria
; ===============================================
show_short_range_scan:
    lda #CLS
    jsr print_char

    lda #<txt_srs_title
    sta string_ptr
    lda #>txt_srs_title
    sta string_ptr+1
    jsr print_string

    jsr print_srs_border

    lda #0
    sta temp7

srs_row_loop:
    jsr print_grid_row

    ; Infos à droite selon la ligne
    lda temp7
    cmp #0
    bne srs_row1
    lda #' '
    jsr print_char
    lda #<txt_quad_short
    sta string_ptr
    lda #>txt_quad_short
    sta string_ptr+1
    jsr print_string
    lda Q2
    jsr print_num
    lda #','
    jsr print_char
    lda Q1
    jsr print_num
    jmp srs_next_row

srs_row1:
    cmp #1
    bne srs_row2
    lda #' '
    jsr print_char
    lda #<txt_sect_short
    sta string_ptr
    lda #>txt_sect_short
    sta string_ptr+1
    jsr print_string
    lda S2
    jsr print_num
    lda #','
    jsr print_char
    lda S1
    jsr print_num
    jmp srs_next_row

srs_row2:
    cmp #2
    bne srs_row3
    lda #' '
    jsr print_char
    lda #<txt_date_short
    sta string_ptr
    lda #>txt_date_short
    sta string_ptr+1
    jsr print_string
    lda T
    sta temp1
    lda T_hi
    sta temp2
    jsr print_16bit_from_temp
    ; Afficher tiret + date limite (T0 + T9)
    lda #'-'
    jsr print_char
    lda T0
    clc
    adc T9
    sta temp1
    lda T0_hi
    adc #0
    sta temp2
    jsr print_16bit_from_temp
    jmp srs_next_row

srs_row3:
    cmp #3
    bne srs_row4
    lda #' '
    jsr print_char
    lda #<txt_energy
    sta string_ptr
    lda #>txt_energy
    sta string_ptr+1
    jsr print_string
	jsr print_16bit
    jmp srs_next_row

srs_row4:
    cmp #4
    bne srs_row5
    lda #' '
    jsr print_char
    lda #<txt_shield_short
    sta string_ptr
    lda #>txt_shield_short
    sta string_ptr+1
    jsr print_string
    lda S
    sta temp1
    lda S_hi
    sta temp2
    jsr print_16bit_from_temp
    jmp srs_next_row

srs_row5:
    cmp #5
    bne srs_row6
    lda #' '
    jsr print_char
    lda #<txt_torp_short
    sta string_ptr
    lda #>txt_torp_short
    sta string_ptr+1
    jsr print_string
    lda P
    jsr print_num
    jmp srs_next_row

srs_row6:
    cmp #6
    bne srs_row7
    lda #' '
    jsr print_char
    lda #<txt_klingons
    sta string_ptr
    lda #>txt_klingons
    sta string_ptr+1
    jsr print_string
    lda K3
    jsr print_num
    jmp srs_next_row

srs_row7:
    cmp #7
    bne srs_next_row
    lda #' '
    jsr print_char
    lda docked_flag
    beq srs_not_docked
    lda #<txt_docked_status
    sta string_ptr
    lda #>txt_docked_status
    sta string_ptr+1
    jsr print_string
    jmp srs_next_row

srs_not_docked:
    lda K3
    beq srs_green
    lda #<txt_red
    sta string_ptr
    lda #>txt_red
    sta string_ptr+1
    jsr print_string
    jmp srs_next_row

srs_green:
    lda #<txt_green
    sta string_ptr
    lda #>txt_green
    sta string_ptr+1
    jsr print_string

srs_next_row:
    jsr print_crlf
    inc temp7
    lda temp7
    cmp #8
    beq srs_bottom
    jmp srs_row_loop

srs_bottom:
    jsr print_srs_border

    ; Systèmes endommagés sous la grille
    jsr print_damaged_systems

    lda #<txt_legend
    sta string_ptr
    lda #>txt_legend
    sta string_ptr+1
    jmp print_string

; ===============================================
; SCANNER AVEC CROIX DIRECTIONNELLE
; ===============================================
show_srs_with_compass:
    lda #CLS
    jsr print_char

    lda #<txt_srs_title
    sta string_ptr
    lda #>txt_srs_title
    sta string_ptr+1
    jsr print_string

    jsr print_srs_border

    lda #0
    sta temp7

srsc_row_loop:
    jsr print_grid_row

    ; Croix directionnelle et stats à droite
    lda temp7
    cmp #0
    bne srsc_row1_check
    ; "1   2   3"
    lda #'1'
    jsr print_char
    lda #' '
    jsr print_char
    lda #' '
    jsr print_char
    lda #' '
    jsr print_char
    lda #'2'
    jsr print_char
    lda #' '
    jsr print_char
    lda #' '
    jsr print_char
    lda #' '
    jsr print_char
    lda #'3'
    jsr print_char
    jmp srsc_next_row

srsc_row1_check:
    cmp #1
    bne srsc_row2_check
    ; " \  :  /"
    lda #' '
    jsr print_char
    lda #'\'
    jsr print_char
    lda #' '
    jsr print_char
    lda #' '
    jsr print_char
    lda #':'
    jsr print_char
    lda #' '
    jsr print_char
    lda #' '
    jsr print_char
    lda #'/'
    jsr print_char
    jmp srsc_next_row

srsc_row2_check:
    cmp #2
    bne srsc_row3_check
    ; "4--<*>--6"
    lda #'4'
    jsr print_char
    lda #'-'
    jsr print_char
    lda #'-'
    jsr print_char
    lda #'<'
    jsr print_char
    lda #'*'
    jsr print_char
    lda #'>'
    jsr print_char
    lda #'-'
    jsr print_char
    lda #'-'
    jsr print_char
    lda #'6'
    jsr print_char
    jmp srsc_next_row

srsc_row3_check:
    cmp #3
    bne srsc_row4_check
    ; " /  :  \"
    lda #' '
    jsr print_char
    lda #'/'
    jsr print_char
    lda #' '
    jsr print_char
    lda #' '
    jsr print_char
    lda #':'
    jsr print_char
    lda #' '
    jsr print_char
    lda #' '
    jsr print_char
    lda #'\'
    jsr print_char
    jmp srsc_next_row

srsc_row4_check:
    cmp #4
    bne srsc_row5_check
    ; "7   8   9"
    lda #'7'
    jsr print_char
    lda #' '
    jsr print_char
    lda #' '
    jsr print_char
    lda #' '
    jsr print_char
    lda #'8'
    jsr print_char
    lda #' '
    jsr print_char
    lda #' '
    jsr print_char
    lda #' '
    jsr print_char
    lda #'9'
    jsr print_char
    jmp srsc_next_row

srsc_row5_check:
    cmp #5
    bne srsc_row6_check
    ; "E:xxxx"
    lda #'E'
    jsr print_char
    lda #':'
    jsr print_char
    jsr print_16bit
    jmp srsc_next_row

srsc_row6_check:
    cmp #6
    bne srsc_row7_check
    ; "B:xxxx"
    lda #'B'
    jsr print_char
    lda #':'
    jsr print_char
    lda S
    sta temp1
    lda S_hi
    sta temp2
    jsr print_16bit_from_temp
    jmp srsc_next_row

srsc_row7_check:
    cmp #7
    bne srsc_next_row
    ; "T:xx"
    lda #'T'
    jsr print_char
    lda #':'
    jsr print_char
    lda P
    jsr print_num

srsc_next_row:
    jsr print_crlf
    inc temp7
    lda temp7
    cmp #8
    beq srsc_done
    jmp srsc_row_loop

srsc_done:
    jsr print_srs_border

    lda #<txt_legend
    sta string_ptr
    lda #>txt_legend
    sta string_ptr+1
    jmp print_string

; ===============================================
; VÉRIFIER AMARRAGE
; DIR EN GREY - VINUSHKA
; ===============================================
check_docking:
    lda B3
    bne cd_check_pos
    lda #0
    sta docked_flag
    rts

cd_check_pos:
    lda B_pos
    sta temp1
    lda B_pos+1
    sta temp2

    ; Distance X
    lda S1
    sec
    sbc temp1
    bcs cd_abs1
    eor #$FF
    clc
    adc #1
cd_abs1:
    cmp #2
    bcc cd_check_y
    jmp cd_not_docked

cd_check_y:
    ; Distance Y
    lda S2
    sec
    sbc temp2
    bcs cd_abs2
    eor #$FF
    clc
    adc #1
cd_abs2:
    cmp #2
    bcc cd_is_docked
    jmp cd_not_docked

cd_is_docked:
    lda docked_flag
    pha
    lda #1
    sta docked_flag
    pla
    cmp #1
    bne cd_new_dock
    jmp cd_already

cd_new_dock:
    lda #CLS
    jsr print_char

    lda #<txt_docked
    sta string_ptr
    lda #>txt_docked
    sta string_ptr+1
    jsr print_string
    jsr wait_key_press

    ; Ravitaillement complet
    lda #<3000
    sta E
    lda #>3000
    sta E_hi
    lda #10
    sta P

    ; Réparer tous les systèmes
    lda #0
    sta DMG_WARP
    sta DMG_LRS
    sta DMG_SRS
    sta DMG_PHASERS
    sta DMG_TORPS
    sta DMG_SHIELDS
    sta DMG_COMPUTER
    sta DMG_DAMAGE

    lda #1
    rts

cd_already:
    lda #0
    rts

cd_not_docked:
    lda #0
    sta docked_flag
    rts

; ===============================================
; AFFICHER COMMANDES
; DIR EN GREY - THE BLOSSOMING BEELZEBUB
; ===============================================
show_commands:
    lda #<txt_commands
    sta string_ptr
    lda #>txt_commands
    sta string_ptr+1
    jmp print_string

; ===============================================
; OBTENIR COMMANDE
; DIR EN GREY - VANITAS
; ===============================================
get_command:
    lda #<txt_prompt
    sta string_ptr
    lda #>txt_prompt
    sta string_ptr+1
    jsr print_string

gc_wait:
    jsr keepalive_tick
    jsr GET_KEY
    bcc gc_wait

    pha

    ; Convertir en majuscule si nécessaire
    cmp #'a'
    bcc gc_already_upper
    cmp #'z'+1
    bcs gc_already_upper
    sec
    sbc #$20
    jmp gc_use_upper

gc_already_upper:
    pla
    pha

gc_use_upper:
    ; Vérifier commande valide
    cmp #'N'
    beq gc_valid
    cmp #'P'
    beq gc_valid
    cmp #'T'
    beq gc_valid
    cmp #'B'
    beq gc_valid
    cmp #'L'
    beq gc_valid
    cmp #'E'
    beq gc_valid
    cmp #'C'
    beq gc_valid
    cmp #'X'
    beq gc_valid

    pla
    jmp gc_wait

gc_valid:
    sta temp3
    pla
    jmp print_crlf

; ===============================================
; EXÉCUTER COMMANDE
; DIR EN GREY - DECAYED CROW (Remix)
; ===============================================
execute_command:
    lda temp3

    cmp #'N'
    beq ec_nav
    cmp #'P'
    beq ec_phasers
    cmp #'T'
    beq ec_torpedoes
    cmp #'B'
    beq ec_shields
    cmp #'L'
    beq ec_lrs
    cmp #'E'
    beq ec_damage
    cmp #'C'
    beq ec_computer
    cmp #'X'
    beq ec_quit
    rts

ec_nav:
    jmp navigate
ec_phasers:
    jmp fire_phasers
ec_torpedoes:
    jmp fire_torpedoes
ec_shields:
    jmp adjust_shields
ec_lrs:
    jmp long_range_scan
ec_damage:
    jmp damage_report
ec_computer:
    jmp library_computer
ec_quit:
    ; Demander confirmation
    lda #CLS
    jsr print_char
    lda #<txt_quit_confirm
    sta string_ptr
    lda #>txt_quit_confirm
    sta string_ptr+1
    jsr print_string
    
    ; Attendre réponse O/N
    jsr get_key
    
    ; Vérifier si O ou o
    cmp #'O'
    beq ec_quit_yes
    cmp #'o'
    beq ec_quit_yes
    
    ; Non, retour au jeu
    rts
    
ec_quit_yes:
    jmp start

; ===============================================
; NAVIGATION
; DIR EN GREY - Unraveling (Unplugged Ver.)
; ===============================================
navigate:
    lda #CLS
    jsr print_char

    jsr show_srs_with_compass
    jsr print_crlf

    ; Demander course
    lda #<txt_nav_course
    sta string_ptr
    lda #>txt_nav_course
    sta string_ptr+1
    jsr print_string

nav_wait_c:
    jsr GET_KEY
    bcc nav_wait_c
    cmp #'1'
    bcc nav_wait_c
    cmp #'9'+1
    bcs nav_wait_c

    pha
    jsr print_crlf
    pla
    sec
    sbc #'0'
    sta course

    ; Demander vitesse Warp
    lda #<txt_nav_warp
    sta string_ptr
    lda #>txt_nav_warp
    sta string_ptr+1
    jsr print_string

    lda DMG_WARP
    beq nav_max8
    lda #<txt_warp_max2
    sta string_ptr
    lda #>txt_warp_max2
    sta string_ptr+1
    jsr print_string
    jmp nav_warp_input

nav_max8:
    lda #<txt_warp_max8
    sta string_ptr
    lda #>txt_warp_max8
    sta string_ptr+1
    jsr print_string

nav_warp_input:
    jsr GET_KEY
    bcc nav_warp_input
    cmp #'0'
    bcc nav_warp_input
    cmp #'9'+1
    bcs nav_warp_input

    sec
    sbc #'0'
    sta warp_factor

    ; Vérifier limite si endommagé
    lda DMG_WARP
    beq nav_w_ok
    lda warp_factor
    cmp #3
    bcc nav_w_ok

    lda #CLS
    jsr print_char
    lda #<txt_warp_damaged
    sta string_ptr
    lda #>txt_warp_damaged
    sta string_ptr+1
    jsr print_msg_wait
    rts

nav_w_ok:
    lda warp_factor
    clc
    adc #'0'
    jsr print_char
    jsr print_crlf

    ; Table de pas selon Warp
    ; 0=64, 1=1, 2=2, 3=3, 4=4, 5=4, 6=6, 7=7, 8=16, 9=32
    lda warp_factor
    beq nav_warp0
    cmp #1
    beq nav_warp1
    cmp #2
    beq nav_warp2
    cmp #3
    beq nav_warp3
    cmp #4
    beq nav_warp4
    cmp #5
    beq nav_warp5
    cmp #6
    beq nav_warp6
    cmp #7
    beq nav_warp7
    cmp #8
    beq nav_warp8
    cmp #9
    beq nav_warp9

nav_warp0:
    lda #64
    jmp nav_set_steps
nav_warp1:
    lda #1
    jmp nav_set_steps
nav_warp2:
    lda #2
    jmp nav_set_steps
nav_warp3:
    lda #3
    jmp nav_set_steps
nav_warp4:
    lda #4
    jmp nav_set_steps
nav_warp5:
    lda #4
    jmp nav_set_steps
nav_warp6:
    lda #6
    jmp nav_set_steps
nav_warp7:
    lda #7
    jmp nav_set_steps
nav_warp8:
    lda #16
    jmp nav_set_steps
nav_warp9:
    lda #32

nav_set_steps:
    sta temp1

    ; Warp 0 = pas de mouvement
    beq nav_no_move

    sta temp2

    ; Vérifier énergie
    lda E_hi
    bne nav_energy_ok
    lda E
    cmp temp1
    bcs nav_energy_ok

    lda #CLS
    jsr print_char
    lda #<txt_insuf_energy
    sta string_ptr
    lda #>txt_insuf_energy
    sta string_ptr+1
    jsr print_msg_wait
    rts

nav_no_move:
    lda #CLS
    jsr print_char
    lda #<txt_no_move
    sta string_ptr
    lda #>txt_no_move
    sta string_ptr+1
    jsr print_msg_wait
    rts

nav_energy_ok:
    ; Sauvegarder position de départ
    lda Q1
    sta temp6
    lda Q2
    sta temp7
    lda S1
    sta temp8
    lda S2
    sta temp9

nav_move_loop:
    lda S1
    sta temp3
    lda S2
    sta temp4

    ; Mouvement Y selon course
    lda course
    cmp #1
    beq nav_up
    cmp #2
    beq nav_up
    cmp #3
    beq nav_up
    cmp #7
    beq nav_down
    cmp #8
    beq nav_down
    cmp #9
    beq nav_down
    jmp nav_x_move

nav_up:
    dec temp4
    jmp nav_x_move

nav_down:
    inc temp4

nav_x_move:
    ; Mouvement X selon course
    lda course
    cmp #1
    beq nav_left
    cmp #4
    beq nav_left
    cmp #7
    beq nav_left
    cmp #3
    beq nav_right
    cmp #6
    beq nav_right
    cmp #9
    beq nav_right
    jmp nav_check_bounds

nav_left:
    dec temp3
    jmp nav_check_bounds

nav_right:
    inc temp3

nav_check_bounds:
    ; Limites secteur → changement de quadrant
    lda temp3
    beq nav_q_left_adj
    cmp #9
    bcs nav_q_right_adj
    jmp nav_check_y

nav_q_left_adj:
    dec Q1
    lda #8
    sta temp3
    jmp nav_check_y

nav_q_right_adj:
    inc Q1
    lda #1
    sta temp3

nav_check_y:
    lda temp4
    beq nav_q_up_adj
    cmp #9
    bcs nav_q_down_adj
    jmp nav_update_pos

nav_q_up_adj:
    dec Q2
    lda #8
    sta temp4
    jmp nav_update_pos

nav_q_down_adj:
    inc Q2
    lda #1
    sta temp4

nav_update_pos:
    ; Limites galaxie
    lda Q1
    bne nav_q1_ok
    jmp nav_galaxy_limit
nav_q1_ok:
    cmp #9
    bcc nav_q1_valid
    jmp nav_galaxy_limit
nav_q1_valid:
    lda Q2
    bne nav_q2_ok
    jmp nav_galaxy_limit
nav_q2_ok:
    cmp #9
    bcc nav_q2_valid
    jmp nav_galaxy_limit
nav_q2_valid:

    ; Vérifier collision étoile
    lda temp4
    sec
    sbc #1
    asl
    asl
    asl
    sta temp5
    lda temp3
    sec
    sbc #1
    clc
    adc temp5
    tax

    lda quadrant,x
    cmp #3
    beq nav_hit_star

    ; Mettre à jour position
    lda temp3
    sta S1
    lda temp4
    sta S2

    ; Consommer 1 énergie
    lda E
    sec
    sbc #1
    sta E
    lda E_hi
    sbc #0
    sta E_hi

    dec temp2
    beq nav_all_steps_done
    jmp nav_move_loop

nav_hit_star:
    ; Effacer anciennes positions Enterprise
    ldx #0
nav_hs_clear:
    lda quadrant,x
    cmp #4
    bne nav_hs_next
    lda #0
    sta quadrant,x
nav_hs_next:
    inx
    cpx #64
    bne nav_hs_clear

    ; Placer Enterprise à S1, S2
    lda S2
    sec
    sbc #1
    asl
    asl
    asl
    sta temp5
    lda S1
    sec
    sbc #1
    clc
    adc temp5
    tax
    lda #4
    sta quadrant,x

    lda #CLS
    jsr print_char

    ; -20 énergie
    lda E
    sec
    sbc #20
    sta E
    lda E_hi
    sbc #0
    sta E_hi

    inc T

    lda #<txt_star_hit
    sta string_ptr
    lda #>txt_star_hit
    sta string_ptr+1
    jsr print_msg_wait
    rts

nav_all_steps_done:
    ; Vérifier changement de quadrant
    lda Q1
    cmp temp6
    bne nav_changed_q
    lda Q2
    cmp temp7
    bne nav_changed_q

    ; Même quadrant - mettre à jour grille
    inc T

    ldx #0
nav_clear_old_e:
    lda quadrant,x
    cmp #4
    bne nav_clear_next
    lda #0
    sta quadrant,x
nav_clear_next:
    inx
    cpx #64
    bne nav_clear_old_e

    lda S2
    sec
    sbc #1
    asl
    asl
    asl
    sta temp5
    lda S1
    sec
    sbc #1
    clc
    adc temp5
    tax

    ; Vérifier si base (ne pas écraser)
    lda quadrant,x
    cmp #2
    beq nav_move_done

    lda #4
    sta quadrant,x

nav_move_done:
    lda #CLS
    jsr print_char
    lda #<txt_moved
    sta string_ptr
    lda #>txt_moved
    sta string_ptr+1
    jsr print_msg_wait
    rts

nav_changed_q:
    inc T
    lda #CLS
    jsr print_char
    lda #<txt_warp
    sta string_ptr
    lda #>txt_warp
    sta string_ptr+1
    jsr print_string
    jsr wait_key_press
    jmp enter_quadrant

nav_galaxy_limit:
    ; Restaurer position
    lda temp6
    sta Q1
    lda temp7
    sta Q2
    lda temp8
    sta S1
    lda temp9
    sta S2

    ; Replacer Enterprise
    ldx #0
ngl_clear:
    lda quadrant,x
    cmp #4
    bne ngl_next
    lda #0
    sta quadrant,x
ngl_next:
    inx
    cpx #64
    bne ngl_clear

    lda S2
    sec
    sbc #1
    asl
    asl
    asl
    sta temp5
    lda S1
    sec
    sbc #1
    clc
    adc temp5
    tax
    lda #4
    sta quadrant,x

    inc T

    lda #CLS
    jsr print_char
    lda #<txt_perimeter
    sta string_ptr
    lda #>txt_perimeter
    sta string_ptr+1
    jsr print_msg_wait
    rts

; ===============================================
; PHASERS
; Melt-Banana - The Call of The Vague
; ===============================================
fire_phasers:
    lda #CLS
    jsr print_char

    lda DMG_PHASERS
    beq fp_ok

    lda #<txt_phasers_damaged
    sta string_ptr
    lda #>txt_phasers_damaged
    sta string_ptr+1
    jmp print_msg_wait

fp_ok:
    lda K3
    bne fp_target

    lda #<txt_no_enemy
    sta string_ptr
    lda #>txt_no_enemy
    sta string_ptr+1
    jmp print_msg_wait

fp_target:
    lda #<txt_phaser_power
    sta string_ptr
    lda #>txt_phaser_power
    sta string_ptr+1
    jsr print_string

fp_wait:
    jsr GET_KEY
    bcc fp_wait
    cmp #'0'
    bcc fp_wait
    cmp #'9'+1
    bcs fp_wait

    sec
    sbc #'0'

    ; Multiplier par ~100
    sta temp1
    asl
    sta temp2
    lda temp1
    asl
    asl
    clc
    adc temp2           ; × 10
    asl
    asl
    asl
    asl                 ; × 160 (approx ×100)
    sta temp1

    lda temp1
    clc
    adc #'0'
    jsr print_char
    jsr print_crlf

    ; Vérifier énergie
    lda E_hi
    bne fp_fire
    lda E
    cmp temp1
    bcs fp_fire

    lda #<txt_insuf_energy
    sta string_ptr
    lda #>txt_insuf_energy
    sta string_ptr+1
    jmp print_msg_wait

fp_fire:
    ; Consommer énergie
    lda E
    sec
    sbc temp1
    sta E
    lda E_hi
    sbc #0
    sta E_hi

    ; Diviser puissance par nombre de Klingons
    lda temp1
    sta temp2
    lda K3
    sta temp3

    lda #0
    sta temp4
fp_div:
    lda temp2
    cmp temp3
    bcc fp_div_done
    sec
    sbc temp3
    sta temp2
    inc temp4
    jmp fp_div

fp_div_done:
    lda temp4
    sta temp1

    ; Attaquer chaque Klingon
    ldx #0
fp_loop:
    lda K3
    beq fp_done
    cpx #3
    beq fp_done

    ; Offset données = X × 3
    txa
    asl
    sta temp2
    txa
    clc
    adc temp2
    tay

    ; Vivant ?
    lda $0042,y
    beq fp_next

    ; Dégâts aléatoires ±50%
    jsr random
    and #$3F
    sec
    sbc #$20
    clc
    adc temp1
    sta temp5

    ; Soustraire des boucliers
    lda $0042,y
    sec
    sbc temp5
    bcs fp_alive

    ; Klingon détruit
    lda #0
    sta $0042,y
    dec K3
    dec K9

    sty temp9
    jsr update_galaxy_minus_klingon

    lda #<txt_klingon_destroyed
    sta string_ptr
    lda #>txt_klingon_destroyed
    sta string_ptr+1
    jsr print_string
    jsr sound_destroy

    ldy temp9

    ; Retirer de grille
    lda K_data+1,y
    sec
    sbc #1
    asl
    asl
    asl
    sta temp2
    lda K_data,y
    sec
    sbc #1
    clc
    adc temp2
    tax
    lda #0
    sta quadrant,x
    jmp fp_next

fp_alive:
    sta $0042,y

    lda #<txt_hit
    sta string_ptr
    lda #>txt_hit
    sta string_ptr+1
    jsr print_string

fp_next:
    inx
    jmp fp_loop

fp_done:
    jmp wait_key_press

; ===============================================
; TORPILLES PHOTONIQUES
; Melt-Banana - Last target on the Last day
; ===============================================
fire_torpedoes:
    lda #CLS
    jsr print_char

    lda P
    bne ft_ok

    lda #<txt_no_torps
    sta string_ptr
    lda #>txt_no_torps
    sta string_ptr+1
    jmp print_msg_wait

ft_ok:
    lda DMG_TORPS
    beq ft_ok2

    lda #<txt_torps_damaged
    sta string_ptr
    lda #>txt_torps_damaged
    sta string_ptr+1
    jmp print_msg_wait

ft_ok2:
    dec P

    jsr show_srs_with_compass
    jsr print_crlf

ft_wait:
    jsr GET_KEY
    bcc ft_wait
    cmp #'1'
    bcc ft_wait
    cmp #'9'+1
    bcs ft_wait

    pha
    jsr print_crlf
    pla
    sec
    sbc #'0'
    sta course

    ; Position départ torpille
    lda S1
    sta temp1
    lda S2
    sta temp2

    ; Consommer 2 énergie
    lda E
    sec
    sbc #2
    sta E
    lda E_hi
    sbc #0
    sta E_hi

ft_move:
    ; Déplacer torpille selon direction
    lda course

    ; Mouvement Y
    cmp #1
    beq ft_up
    cmp #2
    beq ft_up
    cmp #3
    beq ft_up
    cmp #7
    beq ft_down
    cmp #8
    beq ft_down
    cmp #9
    beq ft_down
    jmp ft_x_move

ft_up:
    dec temp2
    jmp ft_x_move

ft_down:
    inc temp2

ft_x_move:
    ; Mouvement X
    lda course
    cmp #1
    beq ft_left
    cmp #4
    beq ft_left
    cmp #7
    beq ft_left
    cmp #3
    beq ft_right
    cmp #6
    beq ft_right
    cmp #9
    beq ft_right
    jmp ft_check

ft_left:
    dec temp1
    jmp ft_check

ft_right:
    inc temp1

ft_check:
    ; Hors limites ?
    lda temp1
    bne ft_x_ok1
    jmp ft_miss_jmp
ft_x_ok1:
    cmp #9
    bcc ft_x_valid
    jmp ft_miss_jmp
ft_x_valid:
    lda temp2
    bne ft_y_ok1
    jmp ft_miss_jmp
ft_y_ok1:
    cmp #9
    bcc ft_y_valid
    jmp ft_miss_jmp
ft_y_valid:

    ; Index = (Y-1) × 8 + (X-1)
    lda temp2
    sec
    sbc #1
    asl
    asl
    asl
    sta temp3
    lda temp1
    sec
    sbc #1
    clc
    adc temp3
    tax

    lda quadrant,x
    beq ft_move             ; Vide, continuer

    ; Collision
    cmp #1
    bne ft_not_k

    ; Détruire Klingon
    lda #0
    sta quadrant,x

    ldy #0
ft_find_k:
    cpy #3
    beq ft_k_found

    tya
    asl
    sta temp3
    tya
    clc
    adc temp3
    tax

    lda $0040,x
    cmp temp1
    bne ft_next_k
    lda $0041,x
    cmp temp2
    beq ft_k_match

ft_next_k:
    iny
    jmp ft_find_k

ft_k_match:
    lda #0
    sta $0042,x

ft_k_found:
    dec K3
    dec K9

    jsr update_galaxy_minus_klingon

    lda #<txt_klingon_destroyed
    sta string_ptr
    lda #>txt_klingon_destroyed
    sta string_ptr+1
    jsr print_string
    jsr sound_destroy

    ; Retirer de grille
    lda temp2
    sec
    sbc #1
    asl
    asl
    asl
    sta temp3
    lda temp1
    sec
    sbc #1
    clc
    adc temp3
    tax
    lda #0
    sta quadrant,x

    jmp wait_key_press

ft_miss_jmp:
    jmp ft_miss

ft_not_k:
    cmp #3
    bne ft_not_s

    lda #<txt_torp_star
    sta string_ptr
    lda #>txt_torp_star
    sta string_ptr+1
    jmp print_msg_wait

ft_not_s:
    cmp #2
    bne ft_miss

    lda #0
    sta quadrant,x
    dec B3
    dec B9

    lda #CLS
    jsr print_char

    lda #<txt_base_destroyed
    sta string_ptr
    lda #>txt_base_destroyed
    sta string_ptr+1
    jmp print_msg_wait

ft_miss:
    lda #<txt_torp_miss
    sta string_ptr
    lda #>txt_torp_miss
    sta string_ptr+1
    jmp print_msg_wait

; ===============================================
; AJUSTER BOUCLIERS
; Melt-Banana - Infection Defective
; ===============================================
adjust_shields:
    lda #CLS
    jsr print_char

    lda DMG_SHIELDS
    beq as_ok

    lda #<txt_shields_damaged
    sta string_ptr
    lda #>txt_shields_damaged
    sta string_ptr+1
    jmp print_msg_wait

as_ok:
    lda #<txt_shield_prompt
    sta string_ptr
    lda #>txt_shield_prompt
    sta string_ptr+1
    jsr print_string

as_wait:
    jsr GET_KEY
    bcc as_wait
    cmp #'0'
    bcc as_wait
    cmp #'9'+1
    bcs as_wait

    sec
    sbc #'0'

    ; Lookup table → 16-bit value
    tax
    lda shield_table_lo,x
    sta temp1
    lda shield_table_hi,x
    sta temp2

    jsr print_crlf

    ; Calculer transfert
    lda temp1
    sec
    sbc S
    sta temp3
    lda temp2
    sbc S_hi
    sta temp4

    bpl as_increase

as_reduce:
    ; Réduire boucliers → redonner énergie
    lda #0
    sec
    sbc temp3
    sta temp3
    lda #0
    sbc temp4
    sta temp4

    lda E
    clc
    adc temp3
    sta E
    lda E_hi
    adc temp4
    sta E_hi

    lda temp1
    sta S
    lda temp2
    sta S_hi
    jmp as_done

as_increase:
    ; Augmenter boucliers → prendre énergie
    lda E
    sec
    sbc temp3
    sta temp5
    lda E_hi
    sbc temp4
    sta temp6

    bmi as_insuf

    lda temp5
    sta E
    lda temp6
    sta E_hi

    lda temp1
    sta S
    lda temp2
    sta S_hi

as_done:
    lda #<txt_shields_set
    sta string_ptr
    lda #>txt_shields_set
    sta string_ptr+1
    jmp print_msg_wait

as_insuf:
    lda #<txt_insuf_energy
    sta string_ptr
    lda #>txt_insuf_energy
    sta string_ptr+1
    jmp print_msg_wait

; ===============================================
; SCANNER LONGUE PORTÉE
; Melt-Banana - Zero
; ===============================================
long_range_scan:
    lda #CLS
    jsr print_char

    lda DMG_LRS
    beq lrs_ok

    lda #<txt_lrs_damaged
    sta string_ptr
    lda #>txt_lrs_damaged
    sta string_ptr+1
    jmp print_msg_wait

lrs_ok:
    lda #<txt_lrs_title
    sta string_ptr
    lda #>txt_lrs_title
    sta string_ptr+1
    jsr print_string

    lda #<txt_lrs_legend
    sta string_ptr
    lda #>txt_lrs_legend
    sta string_ptr+1
    jsr print_string

    ; Grille 3×3 centrée sur quadrant actuel
    lda Q1
    sec
    sbc #1
    sta temp1

    lda Q2
    sec
    sbc #1
    sta temp2

    ldy #0
lrs_row:
    lda #' '
    jsr print_char

    ldx #0
lrs_col:
    stx lrs_x_save
    sty lrs_y_save

    ; Coordonnées quadrant
    txa
    clc
    adc temp1
    sta temp3

    tya
    clc
    adc temp2
    sta temp4

    ; Limites (1-8)
    lda temp3
    beq lrs_invalid
    cmp #9
    bcs lrs_invalid
    lda temp4
    beq lrs_invalid
    cmp #9
    bcs lrs_invalid

    ; Quadrant actuel ?
    lda temp3
    cmp Q1
    bne lrs_not_current
    lda temp4
    cmp Q2
    bne lrs_not_current

    ; Position Enterprise
    lda #'<'
    jsr print_char
    lda #'E'
    jsr print_char
    lda #'>'
    jsr print_char
    jmp lrs_next

lrs_not_current:
    ; Index galaxy = (Y-1) × 8 + (X-1)
    lda temp4
    sec
    sbc #1
    asl
    asl
    asl
    sta temp5

    lda temp3
    sec
    sbc #1
    clc
    adc temp5
    sta temp5

    ; Marquer exploré
    lda #<z_grid
    sta temp6
    lda #>z_grid
    sta temp7

    ldy temp5
    lda #1
    sta (temp6),y

    ; Afficher données
    lda #<galaxy
    sta temp6
    lda #>galaxy
    sta temp7

    ldy temp5
    lda (temp6),y
    jsr print_quad_data
    jmp lrs_next

lrs_invalid:
    lda #'*'
    jsr print_char
    lda #'*'
    jsr print_char
    lda #'*'
    jsr print_char

lrs_next:
    lda #' '
    jsr print_char

    ldx lrs_x_save
    ldy lrs_y_save

    inx
    cpx #3
    beq lrs_row_next
    jmp lrs_col

lrs_row_next:
    jsr print_crlf

    iny
    cpy #3
    beq lrs_done
    jmp lrs_row

lrs_done:
    jmp wait_key_press

; -----------------------------------------------
; Afficher données quadrant (format KBS)
; Entrée : A = valeur encodée
; -----------------------------------------------
print_quad_data:
    ; Afficher données quadrant format KBS
    ; Entrée : A = valeur encodée (K<<5)|(B<<4)|S
    sta temp6

    ; Extraire et afficher K (bits 7-5)
    lsr
    lsr
    lsr
    lsr
    lsr             ; A = Klingons (0-3)
    clc
    adc #'0'
    jsr print_char

    ; Extraire et afficher B (bit 4)
    lda temp6
    lsr
    lsr
    lsr
    lsr             ; bit 4 → bit 0
    and #$01
    clc
    adc #'0'
    jsr print_char

    ; Extraire et afficher S (bits 3-0)
    lda temp6
    and #$0F
    clc
    adc #'0'
    jmp print_char

; ===============================================
; RAPPORT DE DOMMAGES
; Melt-Banana - Red Data, Red Stage
; ===============================================
damage_report:
    lda #CLS
    jsr print_char

    lda #<txt_dmg_title
    sta string_ptr
    lda #>txt_dmg_title
    sta string_ptr+1
    jsr print_string

    ; Warp
    lda #<txt_dmg_warp
    sta string_ptr
    lda #>txt_dmg_warp
    sta string_ptr+1
    jsr print_string
    lda DMG_WARP
    jsr print_dmg_status

    ; LRS
    lda #<txt_dmg_lrs
    sta string_ptr
    lda #>txt_dmg_lrs
    sta string_ptr+1
    jsr print_string
    lda DMG_LRS
    jsr print_dmg_status

    ; Phasers
    lda #<txt_dmg_phasers
    sta string_ptr
    lda #>txt_dmg_phasers
    sta string_ptr+1
    jsr print_string
    lda DMG_PHASERS
    jsr print_dmg_status

    ; Torpilles
    lda #<txt_dmg_torps
    sta string_ptr
    lda #>txt_dmg_torps
    sta string_ptr+1
    jsr print_string
    lda DMG_TORPS
    jsr print_dmg_status

    ; Boucliers
    lda #<txt_dmg_shields
    sta string_ptr
    lda #>txt_dmg_shields
    sta string_ptr+1
    jsr print_string
    lda DMG_SHIELDS
    jsr print_dmg_status

    ; Proposer réparation Warp si endommagé
    lda DMG_WARP
    beq dr_no_warp_damage

    lda #CR
    jsr print_char
    lda #LF
    jsr print_char
    lda #<txt_repair_warp_option
    sta string_ptr
    lda #>txt_repair_warp_option
    sta string_ptr+1
    jsr print_string

    jsr get_key

    cmp #'W'
    beq dr_do_warp_repair
    cmp #'w'
    beq dr_do_warp_repair
    rts

dr_do_warp_repair:
    ; Vérifier énergie >= 250
    lda E_hi
    bne dr_warp_energy_ok
    lda E
    cmp #250
    bcc dr_no_warp_energy

dr_warp_energy_ok:
    lda E
    sec
    sbc #250
    sta E
    lda E_hi
    sbc #0
    sta E_hi

    lda #0
    sta DMG_WARP

    lda #CLS
    jsr print_char
    lda #<txt_repair_warp_done
    sta string_ptr
    lda #>txt_repair_warp_done
    sta string_ptr+1
    jmp print_msg_wait

dr_no_warp_energy:
    lda #CLS
    jsr print_char
    lda #<txt_repair_no_energy
    sta string_ptr
    lda #>txt_repair_no_energy
    sta string_ptr+1
    jmp print_msg_wait

dr_no_warp_damage:
    jmp wait_key_press

; -----------------------------------------------
; Afficher statut dommage
; Entrée : A = valeur dommage (0=OK)
; -----------------------------------------------
print_dmg_status:
    beq pds_ok

    lda #<txt_dmg_bad
    sta string_ptr
    lda #>txt_dmg_bad
    sta string_ptr+1
    jmp print_string

pds_ok:
    lda #<txt_dmg_ok
    sta string_ptr
    lda #>txt_dmg_ok
    sta string_ptr+1
    jmp print_string

; ===============================================
; ORDINATEUR DE BORD
; OTOBOKE BEAVER - CHU CHU SONG
; ===============================================
library_computer:
    lda #CLS
    jsr print_char

    lda #<txt_computer_title
    sta string_ptr
    lda #>txt_computer_title
    sta string_ptr+1
    jsr print_string

    ; Carte galaxie 8×8
    lda #0
    sta temp10

lc_loop:
    ; Y = (temp10 / 8) + 1
    lda temp10
    lsr
    lsr
    lsr
    clc
    adc #1
    sta temp5

    ; X = (temp10 % 8) + 1
    lda temp10
    and #$07
    clc
    adc #1
    sta temp6

    ; Position actuelle ?
    lda temp6
    cmp Q1
    bne lc_not_current
    lda temp5
    cmp Q2
    bne lc_not_current

    lda #'<'
    jsr print_char
    lda #'E'
    jsr print_char
    lda #'>'
    jsr print_char
    jmp lc_end_quad

lc_not_current:
    ; Exploré ?
    lda #<z_grid
    sta temp7
    lda #>z_grid
    sta temp8

    ldy temp10
    lda (temp7),y
    bne lc_explored

    ; Non exploré
    lda #'*'
    jsr print_char
    lda #'*'
    jsr print_char
    lda #'*'
    jsr print_char
    jmp lc_end_quad

lc_explored:
    lda #<galaxy
    sta temp7
    lda #>galaxy
    sta temp8

    ldy temp10
    lda (temp7),y
    jsr print_quad_data

lc_end_quad:
    lda #' '
    jsr print_char

    ; Fin de ligne tous les 8
    lda temp10
    clc
    adc #1
    sta temp10
    and #$07
    bne lc_continue
    jsr print_crlf

lc_continue:
    lda temp10
    cmp #64
    beq lc_end
    jmp lc_loop

lc_end:
    ; Attendre touche - '+' = commande cachée (carte complète)
    ; Vider buffer clavier
lc_clear_buf:
    jsr GET_KEY
    bcs lc_clear_buf

    lda #<txt_press
    sta string_ptr
    lda #>txt_press
    sta string_ptr+1
    jsr print_string

lc_wait_key:
    jsr GET_KEY
    bcc lc_wait_key

    cmp #'+'
    bne lc_exit
    jmp show_full_map

lc_exit:
    rts

; -----------------------------------------------
; CARTE COMPLÈTE (commande cachée '+')
; -----------------------------------------------
show_full_map:
    lda #CLS
    jsr print_char

    lda #<txt_full_map_title
    sta string_ptr
    lda #>txt_full_map_title
    sta string_ptr+1
    jsr print_string

    lda #0
    sta temp10

sfm_loop:
    ; Position actuelle ?
    lda temp10
    and #$07
    clc
    adc #1
    sta temp6           ; X = col + 1

    lda temp10
    lsr
    lsr
    lsr
    clc
    adc #1
    sta temp5           ; Y = row + 1

    lda temp6
    cmp Q1
    bne sfm_not_current
    lda temp5
    cmp Q2
    bne sfm_not_current

    lda #'<'
    jsr print_char
    lda #'E'
    jsr print_char
    lda #'>'
    jsr print_char
    jmp sfm_end_quad

sfm_not_current:
    ; Afficher données réelles (toujours)
    lda #<galaxy
    sta temp7
    lda #>galaxy
    sta temp8

    ldy temp10
    lda (temp7),y
    jsr print_quad_data

sfm_end_quad:
    lda #' '
    jsr print_char

    ; Fin de ligne tous les 8
    lda temp10
    clc
    adc #1
    sta temp10
    and #$07
    bne sfm_continue
    jsr print_crlf

sfm_continue:
    lda temp10
    cmp #64
    beq sfm_end
    jmp sfm_loop

sfm_end:
    jmp wait_key_press

; ===============================================
; ATTAQUE KLINGONS
; HANABIE - Warning
; ===============================================
klingon_attack:
    lda K3
    bne ka_start
    rts

ka_start:
    jsr move_klingons

    ; Couper tout son résiduel avant affichage texte
    lda #0
    sta VIA_ACR
    sta ka_damage_total     ; Reset compteur dégâts

    lda #<txt_klingon_fire
    sta string_ptr
    lda #>txt_klingon_fire
    sta string_ptr+1
    jsr print_string

    ldx #0
ka_loop:
    cpx #3
    bne ka_continue_loop
    jmp ka_done

ka_continue_loop:
    ; Offset données = X × 3
    txa
    asl
    sta temp1
    txa
    clc
    adc temp1
    tay

    ; Vivant ?
    lda $0042,y
    bne ka_is_alive
    jmp ka_next

ka_is_alive:
    stx temp10
    sty temp9

    ; Position Klingon
    lda $0040,y
    sta temp3
    iny
    lda $0040,y
    sta temp4

    ; Vérification ligne de vue simplifiée
    lda temp3
    cmp S1
    bne ka_check_horiz

    ; Aligné verticalement
    lda temp4
    sec
    sbc S2
    beq ka_fire
    cmp #2
    bcs ka_fire
    cmp #$FF
    beq ka_fire

    ; Vérifier obstacle entre
    lda S2
    clc
    adc temp4
    lsr
    sta temp5
    sec
    sbc #1
    asl
    asl
    asl
    clc
    adc temp3
    sec
    sbc #1
    tax
    lda quadrant,x
    cmp #'*'
    beq ka_blocked_s
    cmp #'B'
    beq ka_blocked_s
    jmp ka_fire

ka_check_horiz:
    lda temp4
    cmp S2
    bne ka_fire

    ; Aligné horizontalement
    lda temp3
    sec
    sbc S1
    beq ka_fire
    cmp #2
    bcs ka_fire
    cmp #$FF
    beq ka_fire

    ; Vérifier obstacle entre
    lda S1
    clc
    adc temp3
    lsr
    sta temp5
    lda temp4
    sec
    sbc #1
    asl
    asl
    asl
    clc
    adc temp5
    sec
    sbc #1
    tax
    lda quadrant,x
    cmp #'*'
    beq ka_blocked_s
    cmp #'B'
    beq ka_blocked_s
    jmp ka_fire

ka_blocked_s:
    ldx temp10
    jmp ka_next

ka_fire:
    ldx temp10
    ldy temp9

    ; Dégâts (20-80)
    jsr random
    and #$3F
    clc
    adc #20
    sta temp2

    ; Boucliers absorbent 50%
    lsr
    sta temp2
    ; Accumuler dégâts reçus
    clc
    adc ka_damage_total
    sta ka_damage_total

    ; Soustraire des boucliers
    lda S
    sec
    sbc temp2
    bcs ka_shields_hold

    ; Boucliers dépassés
    lda temp2
    sec
    sbc S
    sta temp3

    lda #0
    sta S

    ; Dégâts sur énergie
    lda E
    sec
    sbc temp3
    sta E
    lda E_hi
    sbc #0
    sta E_hi

    ; Possibilité de dommage système
    jsr random
    cmp #200
    bcs ka_no_damage
    jsr damage_system

ka_no_damage:
    jmp ka_next

ka_shields_hold:
    sta S

ka_next:
    inx
    jmp ka_loop

ka_done:
    lda K3
    beq ka_exit

    lda #<txt_qapla
    sta string_ptr
    lda #>txt_qapla
    sta string_ptr+1
    jsr print_string

    lda #<txt_damage_taken
    sta string_ptr
    lda #>txt_damage_taken
    sta string_ptr+1
    jsr print_string
    ; Afficher valeur des dégâts
    lda ka_damage_total
    jsr print_num
    lda #<txt_damage_pts
    sta string_ptr
    lda #>txt_damage_pts
    sta string_ptr+1
    jsr print_string
    ; Afficher systèmes endommagés si applicable
    jsr print_damaged_systems

    jsr sound_damage
    jmp wait_key_press

ka_exit:
    rts

; ===============================================
; DÉPLACER LES KLINGONS
; ===============================================
move_klingons:
    lda K3
    bne mk_start
    rts

mk_start:
    ldx #0

mk_loop_all:
    cpx #3
    bcc mk_continue_loop
    jmp mk_done_all

mk_continue_loop:
    ; Offset = X × 3
    stx temp9
    txa
    asl
    sta temp1
    txa
    clc
    adc temp1
    tay

    ; Vivant ?
    lda $0040+2,y
    bne mk_is_alive
    jmp mk_next_klingon

mk_is_alive:
    sty temp8

mk_move:
    ldy temp8
    lda $0040,y
    sta temp3
    iny
    lda $0040,y
    sta temp4

    ; Effacer ancienne position
    lda temp4
    sec
    sbc #1
    asl
    asl
    asl
    sta temp1
    lda temp3
    sec
    sbc #1
    clc
    adc temp1
    tax
    lda #0
    sta quadrant,x

    ; Direction aléatoire
    jsr random
    and #$07
    sta temp9

    ; Nouvelle X
    lda temp3
    ldx temp9

    cpx #0
    beq mk_x_minus
    cpx #3
    beq mk_x_minus
    cpx #5
    beq mk_x_minus
    cpx #2
    beq mk_x_plus
    cpx #4
    beq mk_x_plus
    cpx #7
    beq mk_x_plus
    jmp mk_calc_y

mk_x_minus:
    sec
    sbc #1
    jmp mk_calc_y

mk_x_plus:
    clc
    adc #1

mk_calc_y:
    sta temp5

    lda temp4
    ldx temp9

    cpx #0
    beq mk_y_minus
    cpx #1
    beq mk_y_minus
    cpx #2
    beq mk_y_minus
    cpx #5
    beq mk_y_plus
    cpx #6
    beq mk_y_plus
    cpx #7
    beq mk_y_plus
    jmp mk_check_limits

mk_y_minus:
    sec
    sbc #1
    jmp mk_check_limits

mk_y_plus:
    clc
    adc #1

mk_check_limits:
    sta temp6

    ; Limites (1-8)
    lda temp5
    beq mk_restore
    cmp #9
    bcs mk_restore
    lda temp6
    beq mk_restore
    cmp #9
    bcs mk_restore

    ; Case libre ?
    lda temp6
    sec
    sbc #1
    asl
    asl
    asl
    sta temp1
    lda temp5
    sec
    sbc #1
    clc
    adc temp1
    tax
    lda quadrant,x
    beq mk_do_move
    jmp mk_restore

mk_do_move:
    ldy temp8
    lda temp5
    sta $0040,y
    iny
    lda temp6
    sta $0040,y
    lda #1
    sta quadrant,x

    lda #'+'
    jsr print_char
    jmp mk_next_klingon

mk_restore:
    ; Remettre à l'ancienne position
    lda temp4
    sec
    sbc #1
    asl
    asl
    asl
    sta temp1
    lda temp3
    sec
    sbc #1
    clc
    adc temp1
    tax
    lda #1
    sta quadrant,x

mk_next_klingon:
    ldx temp9
    inx
    jmp mk_loop_all

mk_done_all:
    rts

; Tables de déplacement (référence)
mk_dx_table:
    .byte -1, 0, 1, -1, 1, -1, 0, 1
mk_dy_table:
    .byte -1, -1, -1, 0, 0, 1, 1, 1

; -----------------------------------------------
; Endommager système aléatoire
; -----------------------------------------------
damage_system:
    jsr random
    and #$07
    asl
    tax
    lda sys_damage_tbl,x
    sta temp1
    lda sys_damage_tbl+1,x
    sta temp2

    ldy #0
    lda #1
    sta (temp1),y
    rts

sys_damage_tbl:
    .word DMG_WARP, DMG_LRS, DMG_SRS, DMG_PHASERS
    .word DMG_TORPS, DMG_SHIELDS, DMG_COMPUTER, DMG_DAMAGE

; ===============================================
; AFFICHER SYSTÈMES ENDOMMAGÉS (après attaque)
; ===============================================
print_damaged_systems:
    ; Vérifier chaque système, afficher si DMG != 0
    lda DMG_WARP
    beq pds_lrs
    lda #<txt_sys_warp
    sta string_ptr
    lda #>txt_sys_warp
    sta string_ptr+1
    jsr print_string
pds_lrs:
    lda DMG_LRS
    beq pds_srs
    lda #<txt_sys_lrs
    sta string_ptr
    lda #>txt_sys_lrs
    sta string_ptr+1
    jsr print_string
pds_srs:
    lda DMG_SRS
    beq pds_phasers
    lda #<txt_sys_srs
    sta string_ptr
    lda #>txt_sys_srs
    sta string_ptr+1
    jsr print_string
pds_phasers:
    lda DMG_PHASERS
    beq pds_torps
    lda #<txt_sys_phasers
    sta string_ptr
    lda #>txt_sys_phasers
    sta string_ptr+1
    jsr print_string
pds_torps:
    lda DMG_TORPS
    beq pds_shields
    lda #<txt_sys_torps
    sta string_ptr
    lda #>txt_sys_torps
    sta string_ptr+1
    jsr print_string
pds_shields:
    lda DMG_SHIELDS
    beq pds_computer
    lda #<txt_sys_shields
    sta string_ptr
    lda #>txt_sys_shields
    sta string_ptr+1
    jsr print_string
pds_computer:
    lda DMG_COMPUTER
    beq pds_done
    lda #<txt_sys_computer
    sta string_ptr
    lda #>txt_sys_computer
    sta string_ptr+1
    jsr print_string
pds_done:
    rts

; ===============================================
; VÉRIFIER FIN DE PARTIE
; DIR EN GREY - THE FINAL
; ===============================================
check_game_over:
    ; Victoire ?
    lda K9
    bne cgo_check_defeat

    lda #CLS
    jsr print_char
    jsr sound_victory

    lda #<txt_victory
    sta string_ptr
    lda #>txt_victory
    sta string_ptr+1
    jsr print_string
    jsr wait_key_press
    jmp start

cgo_check_defeat:
    ; Énergie épuisée ?
    lda E_hi
    bne cgo_check_time
    lda E
    bne cgo_check_time

    lda #CLS
    jsr print_char
    jsr sound_defeat

    lda #<txt_defeat
    sta string_ptr
    lda #>txt_defeat
    sta string_ptr+1
    jsr print_string
    jsr wait_key_press
    jmp start

cgo_check_time:
    ; Temps écoulé ? Comparaison 16 bits : T0 + T9 >= T
    lda T0
    clc
    adc T9          ; lo : T0_lo + T9 (T9 est 1 octet)
    cmp T           ; comparer avec T lo
    lda T0_hi
    adc #0          ; propager carry éventuel
    sbc T_hi        ; T0_hi + carry - T_hi
    bcs cgo_ok      ; si >= 0 → pas encore timeout

    lda #CLS
    jsr print_char
    jsr sound_defeat

    lda #<txt_timeout
    sta string_ptr
    lda #>txt_timeout
    sta string_ptr+1
    jsr print_string
    jsr wait_key_press
    jmp start

cgo_ok:
    rts

; ===============================================
; GÉNÉRATEUR ALÉATOIRE
; DIR EN GREY - THE BLOSSOMING BEELZEBUB (Remix)
; ===============================================
random:
    lda rnd_seed
    asl
    asl
    eor rnd_seed
    asl
    eor rnd_seed
    asl
    asl
    eor rnd_seed
    asl
    rol rnd_seed+1
    rol rnd_seed
    lda rnd_seed
    rts

; ===============================================
; ROUTINES D'AFFICHAGE
; Kuroyume - Rock'n'Roll
; ===============================================
print_string:
    ldy #0
ps_loop:
    lda (string_ptr),y
    beq ps_done
    jsr print_char
    iny
    jmp ps_loop
ps_done:
    rts

print_char:
    pha
pc_wait:
    lda ACIA_STATUS
    and #$10
    beq pc_wait
    pla
    sta ACIA_DATA
    rts

print_crlf:
    lda #CR
    jsr print_char
    lda #LF
    jmp print_char

; -----------------------------------------------
; Afficher message puis attendre touche
; Entrée : string_ptr déjà configuré
; -----------------------------------------------
print_msg_wait:
    jsr print_string
    jmp wait_key_press

; -----------------------------------------------
; Afficher nombre 8-bit (0-99)
; Entrée : A = nombre
; -----------------------------------------------
print_num:
    cmp #10
    bcc pn_single

    ldx #0
pn_tens:
    cmp #10
    bcc pn_tens_done
    sec
    sbc #10
    inx
    jmp pn_tens

pn_tens_done:
    pha
    txa
    clc
    adc #'0'
    jsr print_char
    pla

pn_single:
    clc
    adc #'0'
    jmp print_char

; -----------------------------------------------
; Afficher nombre 16-bit
; print_16bit : utilise E/E_hi
; print_16bit_from_temp : utilise temp1/temp2
; -----------------------------------------------
print_16bit:
    lda E
    sta temp1
    lda E_hi
    sta temp2
    ; Fall through

print_16bit_from_temp:
    ; Milliers
    ldx #0
p16_thousands:
    lda temp2
    cmp #3
    bcc p16_hundreds
    bne p16_sub1000
    lda temp1
    cmp #232
    bcc p16_hundreds

p16_sub1000:
    lda temp1
    sec
    sbc #232
    sta temp1
    lda temp2
    sbc #3
    sta temp2
    inx
    jmp p16_thousands

p16_hundreds:
    cpx #0
    beq p16_hundreds_digit
    txa
    clc
    adc #'0'
    jsr print_char

p16_hundreds_digit:
    ldx #0
p16_cent_loop:
    lda temp2
    bne p16_sub100
    lda temp1
    cmp #100
    bcc p16_tens_digit

p16_sub100:
    lda temp1
    sec
    sbc #100
    sta temp1
    lda temp2
    sbc #0
    sta temp2
    inx
    jmp p16_cent_loop

p16_tens_digit:
    txa
    clc
    adc #'0'
    jsr print_char

    lda temp1
    ldx #0
p16_tens_loop:
    cmp #10
    bcc p16_ones_digit
    sec
    sbc #10
    inx
    jmp p16_tens_loop

p16_ones_digit:
    sta temp1
    txa
    clc
    adc #'0'
    jsr print_char

    lda temp1
    clc
    adc #'0'
    jmp print_char

; ===============================================
; ANTI-VEILLE MINITEL (keep-alive)
; Envoie NUL ($00) toutes les ~2s.
; NUL est ignoré par le Minitel sans effet
; graphique ni écho. $0E/$0F sont à éviter :
; $0E (SO) active le mode graphique G1.
; Préserve A et tous les flags (dont Carry).
; ===============================================
keepalive_tick:
    php                 ; Sauvegarder flags (Carry)
    pha                 ; Sauvegarder A

    ; Décrémenter compteur 16 bits
    lda ka_counter
    bne kat_lo_nz
    dec ka_counter_hi
kat_lo_nz:
    dec ka_counter

    ; Compteur != 0 → rien à faire
    lda ka_counter
    ora ka_counter_hi
    bne kat_restore

    ; Compteur = 0 → reset et envoyer NUL
    lda #<500
    sta ka_counter
    lda #>500
    sta ka_counter_hi

    ; Envoyer $0F (SI) uniquement - réinitialise le timer veille
    ; sans $0E qui suit, le prochain caractère texte remet en mode normal
kat_tx_wait:
    lda ACIA_STATUS
    and #$10
    beq kat_tx_wait
    lda #$0F
    sta ACIA_DATA

kat_restore:
    pla                 ; Restaurer A
    plp                 ; Restaurer flags (Carry intact)
    rts

; ===============================================
; SAISIE CLAVIER
; ===============================================
get_key:
gk_wait:
    jsr GET_KEY
    bcc gk_wait
    rts

wait_key_press:
    ; Vider buffer clavier
wk_clear:
    jsr GET_KEY
    bcs wk_clear

    lda #<txt_press
    sta string_ptr
    lda #>txt_press
    sta string_ptr+1
    jsr print_string

wk_loop:
    jsr keepalive_tick
    jsr GET_KEY
    bcc wk_loop
    rts

; ===============================================
; EFFETS SONORES
; BAND-MAID - Thrill
; ===============================================
sound_destroy:
    ldx #$38
    ldy #$02
    jsr play_tone_medium

    ldx #$53
    ldy #$03
    jsr play_tone_medium

    ldx #$70
    ldy #$04
    jmp play_tone_medium

sound_damage:
    ldx #$53
    ldy #$03
    jsr play_tone_medium

    ldx #$70
    ldy #$04
    jmp play_tone_short

sound_victory:
    ldx #$38
    ldy #$02
    jsr play_tone_short

    ldx #$F6
    ldy #$02
    jsr play_tone_short

    ldx #$38
    ldy #$02
    jsr play_tone_short

    ldx #$7B
    ldy #$01
    jmp play_tone_medium

sound_defeat:
    ldx #$53
    ldy #$03
    jsr play_tone_long

    ldx #$F4
    ldy #$03
    jsr play_tone_long

    ldx #$70
    ldy #$04
    jmp play_tone_long

play_tone:
    stx VIA_T1CL
    sty VIA_T1CH
    lda #$C0
    sta VIA_ACR
    rts

stop_tone:
    lda #0
    sta VIA_ACR
    rts

play_tone_short:
    jsr play_tone
    ldx #$18
pts_delay:
    ldy #$FF
pts_d:
    dey
    bne pts_d
    dex
    bne pts_delay
    jmp stop_tone

play_tone_medium:
    jsr play_tone
    ldx #$30
ptm_delay:
    ldy #$FF
ptm_d:
    dey
    bne ptm_d
    dex
    bne ptm_delay
    jmp stop_tone

play_tone_long:
    jsr play_tone
    ldx #$60
ptl_delay:
    ldy #$FF
ptl_d:
    dey
    bne ptl_d
    dex
    bne ptl_delay
    jmp stop_tone

; ===============================================
; MISE À JOUR GALAXY APRÈS DESTRUCTION KLINGON
; ===============================================
update_galaxy_minus_klingon:
    lda Q2
    sec
    sbc #1
    asl
    asl
    asl
    sta temp8
    lda Q1
    sec
    sbc #1
    clc
    adc temp8
    tax

    lda galaxy,x
    sec
    sbc #$20            ; -1 Klingon dans bits 7-5 (au lieu de -100)
    sta galaxy,x
    rts

; ===============================================
; TEXTES
; Dir en grey - Mazohyst Of Decadence
; ===============================================
msg_tit:
	.byte "** EDITION SPECIALE Maker Faire 2026 **",CR,LF,0
msg_intro:
    .byte "__________________         _-_",CR,LF
    .byte "\__(=========/_=_/ ___.---'---'---.___",CR,LF
    .byte "           \_ \    \---._________.---'",CR,LF
    .byte " Ver. V5.12  \ \   /  /   '-_-'",CR,LF
    .byte "         __,--`.`-'..'-_",CR,LF
    .byte "        /___  NCC-1701 ||",CR,LF
    .byte "             `--.____,-'",CR,LF,0

msg_intro1:
    .byte CR,LF
    .byte " ** SUPER STAR TREK **",CR,LF
    .byte " Memo-1/Minitel",CR,LF
    .byte " Par BipCollector & Claude",CR,LF,CR,LF,0

msg_mission1:
    .byte "VOS ORDRES: Commandant.",CR,LF
    .byte " Detruire les ",0

msg_mission2:
    .byte " vaisseaux",CR,LF
    .byte " Klingons avant la date ",0

msg_mission3:
    .byte ".",CR,LF
    .byte " Vous avez ",0

msg_mission4:
    .byte " jours.",CR,LF
    .byte " Il y a ",0

msg_mission5:
    .byte " base(s) stellaire(s)",CR,LF,0

txt_srs_title:
    .byte "-- SCANNER --",CR,LF,0

txt_legend:
    .byte "E=Vous K=Klingon B=Base *=Etoile",CR,LF,0

txt_quad_short:
    .byte " Quadr.:",0

txt_sect_short:
    .byte " Sect. :",0

txt_date_short:
    .byte " Date:",0

txt_energy:
    .byte " Eng:",0

txt_torp_short:
    .byte " Tor:",0

txt_shield_short:
    .byte " Bcl:",0

txt_klingons:
    .byte " Klg:",0

txt_docked_status:
    .byte " AMARRE",0

txt_red:
    .byte " CODE: ROUGE",0

txt_green:
    .byte " CODE: VERT",0

txt_commands:
    .byte CR,LF,"N:Nav  P:Phas  T:Torp  B:Bouc",CR,LF
    .byte         "L:LRS  E:Etat  C:Carte X:Quit",CR,LF,0

txt_prompt:
    .byte ">",0

txt_nav_course:
    .byte "NAVIGATION:",CR,LF,0

txt_nav_warp:
    .byte CR,LF
    .byte "Echelle Warp:",CR,LF
    .byte "1=1  2=2  3=3  4=4  5=5  6=6  7=7",CR,LF
    .byte "8=16 9=32 0=64",CR,LF
    .byte CR,LF
    .byte " Facteur Warp (0-",0

txt_warp_max8:
    .byte "9): ",0

txt_warp_max2:
    .byte "2): ",0

txt_warp_damaged:
    .byte "MOTEURS WARP ENDOMMAGES!",CR,LF
    .byte "Maximum: Warp 2",CR,LF,0

txt_moved:
    .byte "Deplacement effectue!",CR,LF,0

txt_no_move:
    .byte "Pas de deplacement.",CR,LF,0

txt_warp:
    .byte "** SAUT WARP ***",CR,LF,0

txt_perimeter:
    .byte "PERIMETRE GALACTIQUE!",CR,LF
    .byte "Autorisation refusee.",CR,LF,0

txt_star_hit:
    .byte "** COLLISION ETOILE! **",CR,LF
    .byte "Dommages: -20 energie",CR,LF,0

txt_no_enemy:
    .byte "Aucun ennemi!",CR,LF,0

txt_phaser_power:
    .byte "Puissance Phasers (0-9): ",0

txt_phasers_damaged:
    .byte "PHASERS ENDOMMAGES!",CR,LF,0

txt_klingon_destroyed:
    .byte "** KLINGON DETRUIT **",CR,LF,0

txt_hit:
    .byte "Touche!",CR,LF,0

txt_insuf_energy:
    .byte "Energie insuffisante!",CR,LF,0

txt_no_torps:
    .byte "Plus de torpilles!",CR,LF,0

txt_torps_damaged:
    .byte "TUBES TORPILLES ENDOMMAGES!",CR,LF,0

txt_torp_miss:
    .byte "Torpille manquee!",CR,LF,0

txt_torp_star:
    .byte "Torpille bloquee par etoile!",CR,LF,0

txt_base_destroyed:
    .byte " *** BASE DETRUITE ***",CR,LF
    .byte CR,LF
    .byte "      **/- A**",CR,LF
    .byte "  ___---=*S 1==-*-___",CR,LF
    .byte "( =\  /.**. .\   /__=)",CR,LF
    .byte "  __   *\__O__*--",CR,LF
    .byte "Cour martiale possible!",CR,LF,0

txt_shield_prompt:
	.byte "Boucliers (0-9):",CR,LF
    .byte "0=0  1=100 2=200 3=300 4=400",CR,LF
    .byte "5=500 6=600 7=700 8=800 9=900",CR,LF
    .byte ">",0

txt_shields_damaged:
    .byte " BOUCLIERS ENDOMMAGES!",CR,LF,0

txt_shields_set:
    .byte " Boucliers ajustes!",CR,LF,0

txt_lrs_title:
    .byte "-- SCANNER LRS --",CR,LF,0

txt_lrs_legend:
    .byte "KBS K=Kling B=Base S=Etoiles",CR,LF,CR,LF,0

txt_lrs_damaged:
    .byte " LRS ENDOMMAGE!",CR,LF,0

txt_dmg_title:
    .byte "-- ETAT SYSTEMES --",CR,LF,CR,LF,0

txt_dmg_warp:
    .byte "Moteurs Warp: ",0

txt_dmg_lrs:
    .byte "Scanner LRS: ",0

txt_dmg_phasers:
    .byte "Phasers: ",0

txt_dmg_torps:
    .byte "Torpilles: ",0

txt_dmg_shields:
    .byte "Boucliers: ",0

txt_dmg_ok:
    .byte "OK",CR,LF,0

txt_dmg_bad:
    .byte "ENDOMMAGE",CR,LF,0

txt_repair_warp_option:
    .byte " W:reparer Warp (250E)",CR,LF,0

txt_repair_warp_done:
    .byte " Warp repare! -250E",CR,LF,0

txt_repair_no_energy:
    .byte " Energie insuffisante!",CR,LF,0

txt_computer_title:
    .byte "CARTE GALAXIE:",CR,LF,CR,LF,0

txt_full_map_title:
    .byte "== CARTE COMPLETE ==",CR,LF,CR,LF,0

txt_damage_pts:
    .byte " pts",CR,LF,0

txt_sys_warp:
    .byte "  [!] Moteurs Warp",CR,LF,0
txt_sys_lrs:
    .byte "  [!] Scanner LRS",CR,LF,0
txt_sys_srs:
    .byte "  [!] Scanner SRS",CR,LF,0
txt_sys_phasers:
    .byte "  [!] Phasers",CR,LF,0
txt_sys_torps:
    .byte "  [!] Tubes torpilles",CR,LF,0
txt_sys_shields:
    .byte "  [!] Boucliers",CR,LF,0
txt_sys_computer:
    .byte "  [!] Ordinateur",CR,LF,0

; Séquence Pro2 Minitel 1B - désactivation veille
kat_pro2_seq:
    .byte $1B, $3A, $6A, $23

txt_klingon_fire:
    .byte CR,LF,"! ATTAQUE KLINGONS !",CR,LF,0

txt_damage_taken:
    .byte "Degats recus!",CR,LF,0

txt_qapla:
    .byte "Qapla' !",CR,LF,0

txt_docked:
    .byte "        //-A-\\",CR,LF
    .byte "  ___---==DS1==---___",CR,LF
    .byte "(=__\   /.. ..\   /__=)",CR,LF
    .byte "     ---\__O__/---",CR,LF
    .byte CR,LF
    .byte "BASE STELLAIRE DS1",CR,LF
    .byte CR,LF
    .byte "Amarrage reussi!",CR,LF
    .byte "Ravitaillement complet:",CR,LF
    .byte "- Energie:  3000",CR,LF
    .byte "- Torpilles:10",CR,LF
    .byte "- Boucliers:Conserves",CR,LF
    .byte "- Systemes: Repares",CR,LF
    .byte CR,LF,0

txt_victory:
    .byte CR,LF,CR,LF
    .byte "*** VICTOIRE ! ***",CR,LF,CR,LF
    .byte "Tous les Klingons ont",CR,LF
    .byte "ete detruits!",CR,LF,CR,LF,0

txt_defeat:
    .byte CR,LF,CR,LF
    .byte "*** DEFAITE ! ***",CR,LF,CR,LF
    .byte "L'Enterprise a ete",CR,LF
    .byte "detruit...",CR,LF,CR,LF,0

txt_timeout:
    .byte CR,LF,CR,LF
    .byte "*** TEMPS ECOULE ! ***",CR,LF,CR,LF
    .byte "Mission echouee.",CR,LF,CR,LF,0

txt_quit_confirm:
    .byte CR,LF
    .byte " Quitter le jeu ?",CR,LF
    .byte " (O/N): ",0

txt_press:
    .byte CR,LF,"[Touche pour continuer]",CR,LF,0

; -----------------------------------------------
; Tables
; -----------------------------------------------
shield_table_lo:
    .byte <0, <100, <200, <300, <400, <500, <600, <700, <800, <900
shield_table_hi:
    .byte >0, >100, >200, >300, >400, >500, >600, >700, >800, >900