# Database

IGN GPAO Database est le modèle de données de la base [GPAO](https://github.com/ign-gpao).
Pour faciliter son déploiement, ce modèle de données a été dockerisé à partir d'une image officielle de postgres disponible sur [DockerHub](https://hub.docker.com/_/postgres).

## Prérequis

 - Dans le cas d'une utilisation sur un serveur postgres déjà existant, il est nécessaire d'avoir un serveur postgres >= 13 avec un compte admin.
 - Docker dans le cas d'une utilisation à travers docker. Pour l'installation de docker c'est par [ici](https://docs.docker.com/engine/install/).

## Modèle de données

![Modèle de données de la GPAO](https://github.com/ign-gpao/database/blob/main/images/GPAO%20V3.png)

## Utilisation

### Avec un serveur postgres existant

Appliquer le script `sql/gpao.sql` via la commande psql :

``` bash
psql -U POSTGRES_ADMIN -h SERVEUR_NAME -f PATH_TO/gpao.sql
```

Avec ``` POSTGRES_ADMIN ``` = le login postgres avec les droits d'administration et ``` SERVER_NAME ``` = le nom de la machine hébergeant postgres.

Ce script va créer une nouvelle base de données appelée ``` gpao ``` avec l'ensemble des tables, vues, fonctions, etc., nécessaire au bon fonctionnement de la GPAO.

**Remarque** : Si une base portant le nom gpao est déjà présente, il faudra soit adapter les premières lignes du script SQL ``` CREATE DATABASE gpao ... ``` soit la renommer ou la supprimer.

### Avec Docker

Une image déjà construite est accessible depuis [DockerHub](https://hub.docker.com/r/gpao/database) et peut être directement récupérée via la commande :

``` bash
docker pull gpao/database:latest
```

Lorsque l'image est téléchargée, il suffit d'executer la commande :

``` bash
docker run -ti -p 5432:5432 --name database -e POSTGRES_PASSWORD=postgres
```

Par défaut, les données de la base ont pour durée de vie celle du container, si vous souhaitez rendre persistentes les données, il faut ajouter l'option :

``` bash
-v PATH_TO_SAVE:/var/lib/postgresql/data
```

## Pour les développeurs

### Génération du fichier gpao.sql

Après avoir modifié localement le modèle de données, on souhaite parfois re-générer le fichier gpao.sql associé. Pour cela, dans le répertoire de la database :
* Lancer le conteneur de la database, effectuer les modifications souhaitées du modèle de données (soit via pgAdmin, soit via psql)
* Ouvrir un environnement d’exécution dans le conteneur avec la commande `docker exec -ti database bash`
* Générer le nouveau fichier gpao.sql à partir de la base du conteneur via la commande `pg_dump -U postgres -h localhost -C -s gpao > gpao.sql`
* Quitter l'environnement d’exécution du conteneur avec `exit`
* Copier le fichier généré ici à la racine du conteneur dans le répertoire local de la database via la commande `docker cp database:/gpao.sql .`

## Licence

Ce projet est sous licence CECILL-B (voir [LICENSE.md](https://github.com/ign-gpao/.github/blob/main/LICENSE.md)).

[![IGN](https://github.com/ign-gpao/.github/blob/main/images/logo_ign.png)](https://www.ign.fr):
